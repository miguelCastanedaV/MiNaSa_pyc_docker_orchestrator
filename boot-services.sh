#!/bin/bash

source ./common/boot-service-resources.sh

# Si el primer argumento es un archivo de entorno existente (.env o .env.*), lo usamos
if [ $# -ge 1 ] && [ -f "$1" ] && [[ "$1" =~ ^\.env(\.|$) ]]; then
    export SELECTED_ENV_FILE="$1"
    shift  # quitar el primer argumento
    echo "✅ Archivo de entorno especificado: $SELECTED_ENV_FILE"
fi

# Cargar el entorno (pregunta si es necesario)
select_and_load_env

# Determinar el archivo compose según el entorno cargado
COMPOSE_FILE=$(get_compose_file "$SELECTED_ENV_FILE")
export COMPOSE_FILE
echo "📄 Usando archivo compose: $COMPOSE_FILE"

# Función para ejecutar docker compose con el entorno y archivo seleccionados
docker_compose() {
    local cmd="docker compose --env-file \"$SELECTED_ENV_FILE\""

    if [[ "$ENV_NAME" != "local" ]] && [[ -f "versions.${ENV_NAME}.env" ]]; then
        cmd="$cmd --env-file versions.${ENV_NAME}.env"
    fi

    cmd="$cmd -f \"$COMPOSE_FILE\" $*"
    eval "$cmd"
}

if [ $# -eq 0 ]; then
    show_menu
    read -p "Option: " option
else
    case "$1" in
        update)
            shift
            service="$1"
            if [ -z "$service" ]; then
                echo "⚠️ No se especificó servicio. Iniciando modo interactivo..."
                update_service_interactive
                exit $?
            fi
            shift

            migrate_flag=false
            while [ $# -gt 0 ]; do
                case "$1" in
                    --migrate) migrate_flag=true ;;
                    *) echo "❌ Opción desconocida: $1"; exit 1 ;;
                esac
                shift
            done

            echo "🔄 Actualizando servicio $service de forma no interactiva..."
            update_service_noninteractive "$service" "$migrate_flag"
            exit $?
            ;;
        rollback)
            shift
            service="$1"
            shift
            target_version=""
            steps=0
            while [ $# -gt 0 ]; do
                case "$1" in
                    --version) target_version="$2"; shift ;;
                    --steps) steps="$2"; shift ;;
                    *) echo "❌ Opción desconocida: $1"; exit 1 ;;
                esac
                shift
            done
            if [ -z "$target_version" ]; then
                echo "❌ Debes especificar la versión objetivo con --version"
                exit 1
            fi
            rollback_service_noninteractive "$service" "$target_version" "$steps"
            exit $?
            ;;
        [0-9]*)
            option="$1"
            shift
            # Si hay más argumentos, se ignoran (podrían ser flags en el futuro)
            if [ $# -gt 0 ]; then
                echo "⚠️  Argumentos adicionales ignorados: $*"
            fi
            ;;
        *)
            echo "❌ Opción o comando desconocido: $1"
            echo "Uso: $0 [<opción> | update <servicio> [--migrate]]"
            echo "  <opción> puede ser un número del 0 al 13"
            exit 1
            ;;
    esac
fi

case $option in
    0)
        echo "Exit..."
        exit 0
    ;;
    1)
        echo "Starting environment..."
        run_config_generator
        run_validations_pre_build
        docker_compose up --build -d
        if [[ $? -ne 0 ]]; then
            echo "❌ Error: The context could not be prepared. Check the specified path."
            exit 1
        fi
        show_logs
    ;;
    2)
        echo -e "\nThis will delete data from Docker's MySQL and recreate services. Do you want to continue? (y/n):"
        read -r confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            # Apagar servicios
            docker_compose down -t 1 2>/dev/null || true

            run_config_generator
            run_validations_pre_build
            echo "Recreating all services..."

            rm -rf "${DASHBOARD_PATH}/vendor" "${DASHBOARD_PATH}/node_modules"
            rm -f "${DASHBOARD_PATH}/.env" "${DASHBOARD_PATH}/.env.worker" "${DASHBOARD_PATH}/.env.testing"

            docker_compose down --rmi all -v --remove-orphans -t 1
            FIRST_SERVICE_BOOT=yes docker_compose up --build -d

            if [[ $? -ne 0 ]]; then
                echo "❌ Error: The context could not be prepared. Check the specified path."
            exit 1
            fi

            update_ssl_certificates
            update_hosts_file
            show_logs
        else
            exec "$0"
        fi
    ;;
    3)
        echo "Restarting all services..."
        docker_compose restart
    ;;
    4)
        update_service_interactive
    ;;
    5)
        echo "Turning off services..."
        docker_compose down -t 1
    ;;
    6)
        show_logs
    ;;
    7)
        echo "Refreshing Databases"
        docker_compose exec mysql "/docker-entrypoint-initdb.d/create_databases.sh"
    ;;
    8)
        update_ssl_certificates
    ;;
    9)
        update_hosts_file
    ;;
    10)
        list_traefik_services
        exit 0
    ;;
    11)
        run_config_generator
        echo "✅ Configuration files generated successfully in ./common/env_vars/generated"
        exit 0
    ;;
    12)
        echo "Build Docker images for registry"
        current_env="${APP_ENV:-local}"

        echo "Ambiente actual: ${current_env} (APP_ENV=${current_env})"
        echo ""

        case "$current_env" in
            production)
                echo "Stages disponibles para producción:"
                echo "  1) production-web (imagen web para producción)"
                echo "  2) production-worker (worker para producción)"
                echo "  3) all (ambas)"
                echo "  4) ci (imagen para integración continua)"

                read -p "Selecciona opciones (ej: 1,2 o 1 2 o all): " stages_input

                stages=()
                stages_input=$(echo "$stages_input" | tr ',' ' ')
                for item in $stages_input; do
                    case "$item" in
                        1) stages+=("production-web") ;;
                        2) stages+=("production-worker") ;;
                        3|all) stages=("production-web" "production-worker") ; break ;;
                        4) stages+=("ci") ;;
                        *) stages+=("$item") ;;
                    esac
                done
                ;;
            uat)
                echo "Stages disponibles para UAT:"
                echo "  1) uat-web (imagen web para UAT)"
                echo "  2) uat-worker (worker para UAT)"
                echo "  3) all (ambas)"
                echo "  4) ci (imagen para integración continua)"

                read -p "Selecciona opciones (ej: 1,2 o 1 2 o all): " stages_input

                stages=()
                stages_input=$(echo "$stages_input" | tr ',' ' ')
                for item in $stages_input; do
                    case "$item" in
                        1) stages+=("uat-web") ;;
                        2) stages+=("uat-worker") ;;
                        3|all) stages=("uat-web" "uat-worker") ; break ;;
                        4) stages+=("ci") ;;
                        *) stages+=("$item") ;;
                    esac
                done
                ;;
            *)
                echo -e "${RED}❌ Ambiente desconocido: ${current_env}${NC}"
                echo "Valores esperados: production, uat, local"
                exit 1
                ;;
        esac

        if [ ${#stages[@]} -eq 0 ]; then
            echo "❌ No valid stages selected"
            exit 1
        fi

        echo "Building stages: ${stages[*]}"
        build_dashboard_images "${stages[@]}"
        exit 0
    ;;
    13)
        echo "Adding local docker registry"
        add_local_docker_registry
        exit 0
    ;;
    14)
        echo -e "\nRealizar rollback de un servicio"
        read -p "Nombre del servicio (pyc-dashboard, public-web): " service
        read -p "Versión objetivo (ej. v1.2.2): " target_version
        read -p "Número de migraciones a revertir (solo pyc-dashboard, default 0): " steps
        steps=${steps:-0}
        rollback_service_noninteractive "$service" "$target_version" "$steps"
    ;;
    15)
      echo -e"\nVer configuración actual del entorno"
      echo "Archivo de entorno cargado: $SELECTED_ENV_FILE"
      docker_compose config
    ;;
    *)
        echo -e "\nInvalid option.\n"
        exec "$0"
    ;;
esac
