#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Variable global para el archivo de entorno seleccionado
SELECTED_ENV_FILE=""
SELECTED_ENV_VERSION_FILE=""

# Mapeo de servicios a variables de entorno en versions.{env}.env
declare -A SERVICE_VERSION_VAR=(
    ["dashboard"]="DASHBOARD_VERSION"
    ["dashboard_worker"]="DASHBOARD_VERSION"
)

select_and_load_env() {
    if [[ -n "$SELECTED_ENV_FILE" && -f "$SELECTED_ENV_FILE" ]]; then
        echo "✅ Usando entorno previamente seleccionado: $SELECTED_ENV_FILE"
        set -a
        source "$SELECTED_ENV_FILE"
        set +a

        # Determinar el nombre del entorno desde APP_ENV
        ENV_NAME="${APP_ENV}"
        export ENV_NAME

        # Solo cargar versions.env si no es local
        if [[ "$ENV_NAME" != "local" ]] && [[ -f "versions.${ENV_NAME}.env" ]]; then
            local versions_file="versions.${ENV_NAME}.env"
            if [[ -f "$versions_file" ]]; then
                echo "✅ Cargando $versions_file"
                set -a
                source "$versions_file"
                set +a
            else
                echo "⚠️ No se encontró $versions_file"
            fi
        fi
        return 0
    fi

    if [[ -f ".env" ]]; then
        echo "✅ Archivo .env encontrado. Cargando variables..."
        SELECTED_ENV_FILE=".env"
        export SELECTED_ENV_FILE
        set -a
        source ".env"
        set +a

        ENV_NAME="${APP_ENV}"
        export ENV_NAME
        # No cargar versions.env en local
        return 0
    fi

    echo "No se encontró el archivo .env"
    echo "Selecciona el entorno:"
    echo "1) production"
    echo "2) uat"
    echo "3) local"
    read -p "Opción: " env_option

    case $env_option in
        1) env_name="production" ;;
        2) env_name="uat" ;;
        3) env_name="local" ;;
        *) echo "❌ Opción inválida"; exit 1 ;;
    esac

    local env_file=".env.${env_name}"
    if [[ ! -f "$env_file" ]]; then
        echo "⚠️  Archivo $env_file no encontrado. Usando .env por defecto (si existe)."
        if [[ -f ".env" ]]; then
            env_file=".env"
            env_name="local"   # Asumimos local si se usa .env por defecto
        else
            echo "❌ No hay ningún archivo de entorno disponible."
            exit 1
        fi
    fi

    echo "✅ Cargando variables desde: $env_file"
    SELECTED_ENV_FILE="$env_file"
    export SELECTED_ENV_FILE
    set -a
    source "$env_file"
    set +a

    ENV_NAME="${APP_ENV:-$env_name}"
    export ENV_NAME

    if [[ "$ENV_NAME" != "local" ]] && [[ -f "versions.${ENV_NAME}.env" ]]; then
        local versions_file="versions.${ENV_NAME}.env"
        if [[ -f "$versions_file" ]]; then
            SELECTED_ENV_VERSION_FILE="$versions_file"
            export SELECTED_ENV_VERSION_FILE

            echo "✅ Cargando $versions_file"
            set -a
            source "$versions_file"
            set +a
        else
            echo "⚠️ No se encontró $versions_file"
        fi
    fi
}

get_compose_file() {
    local env_file="$1"
    case "$env_file" in
        .env.production) echo "docker-compose.production.yml" ;;
        .env.uat)        echo "docker-compose.uat.yml" ;;
        .env.local)      echo "docker-compose.local.yml" ;;
        .env)            echo "docker-compose.local.yml" ;; # Por defecto, asumimos local
        *)               echo "docker-compose.local.yml" ;;
    esac
}

load_env_variables() {
    select_and_load_env
}

show_menu() {
    echo "Select an option:"
    echo "1) Start the environment"
    echo "2) Recreate all services (migrate:fresh)"
    echo "3) Restart all services"
    echo "4) Restart a specific service"
    echo "5) Turn off services"
    echo "6) View docker logs in real time"
    echo "7) Refresh Databases"
    echo "8) Update SSL certificates in selected containers"
    echo "9) Update local hosts file with service domains"
    echo "10) List Traefik managed services"
    echo "11) Generate environment variable files (without starting services)"
    echo "12) Build Docker images for dashboard stages"
    echo "13) Add local docker registry"
    echo "14) Rollback a service to a previous version"
    echo "15) View current docker settings"
    echo "0) Exit"
}

validate_user_uid() {
  echo "Validating USER_UID..."
  local host_uid=$(id -u)
  if [[ "$USER_UID" != "$host_uid" ]]; then
    echo "❌ The USER_UID defined in the environment ($USER_UID) does not match the host user ID ($host_uid)."
    return 1
  else
    echo "✅ The USER_UID matches the host user ID."
    return 0
  fi
}

validate_paths() {
  local variables_paths=("DASHBOARD_PATH")
  echo "Validating paths defined in the environment..."
  local error_found=0
  for var in "${variables_paths[@]}"; do
    local value=${!var}
    if [[ -n "$value" ]]; then
      if [[ ! -d "$value" && ! -f "$value" ]]; then
        echo "❌ The path for $var does not exist: $value"
        error_found=1
      fi
    else
      echo "⚠️ The variable $var is not defined or has no value."
      error_found=1
    fi
  done
  return $error_found
}

validate_ports() {
  local variables_ports=("DB_PORT" "REDIS_PORT" "APP_PORT" "APP_PORT_SSL")
  echo "Validating ports defined in the environment..."
  local error_found=0
  for var in "${variables_ports[@]}"; do
    local port=${!var}
    if [[ -n "$port" ]]; then
      if lsof -i:"$port" > /dev/null 2>&1; then
        echo "❌ The port $port defined in $var is already in use."
        error_found=1
      fi
    else
      echo "⚠️ The variable $var is not defined or has no value."
      error_found=1
    fi
  done
  return $error_found
}

run_validations_pre_build() {
  local error_found=0

  validate_user_uid || error_found=1
  validate_paths || error_found=1
  validate_ports || error_found=1

  if [[ $error_found -eq 1 ]]; then
    exit 1
  fi
}

get_traefik_services() {
    local TRAEFIK_DYNAMIC_FILE="./traefik/traefik_dynamic.local.yml"

    if [ ! -f "$TRAEFIK_DYNAMIC_FILE" ]; then
        echo -e "❌ Archivo no encontrado: $TRAEFIK_DYNAMIC_FILE" >&2
        return 1
    fi

    grep -E "rule:.*Host" "$TRAEFIK_DYNAMIC_FILE" | \
        sed -n 's/.*Host(\([^)]*\)).*/\1/p' | \
        tr -d '`"' | \
        tr ',' '\n' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sort -u
}

list_traefik_services() {
    local APP_PORT_SSL="${APP_PORT_SSL:-443}"
    local APP_PORT="${APP_PORT:-80}"
    local TRAEFIK_PORT="${TRAEFIK_PORT:-8080}"

    echo ""
    echo -e "${BLUE}╭────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BLUE}│${BOLD}  🚀  SERVICIOS TRAEFIK ACTIVOS                              ${BLUE}│${NC}"
    echo -e "${BLUE}╰────────────────────────────────────────────────────────────╯${NC}"
    echo ""

    local count=0
    while IFS= read -r domain; do
        if [[ -n "$domain" ]]; then
            ((count++))
            echo -e "  ${GREEN}▶${NC} ${BOLD}${domain}${NC}"
            echo -e "     🔗 https://${domain}$([[ "$APP_PORT_SSL" != "443" ]] && echo ":${APP_PORT_SSL}")"
            echo -e "     🌐 http://${domain}$([[ "$APP_PORT" != "80" ]] && echo ":${APP_PORT}")"
            echo ""
        fi
    done < <(get_traefik_services)

    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  ${BOLD}📊 PANEL DE CONTROL TRAEFIK${NC}                                ${YELLOW}│${NC}"
    echo -e "${YELLOW}├────────────────────────────────────────────────────────────┤${NC}"

    printf "  %-12s ${BOLD}http://localhost:${TRAEFIK_PORT}/%-20s${NC}\n" "Dashboard:" "dashboard/"
    printf "  %-12s ${BOLD}http://localhost:${TRAEFIK_PORT}/%-20s${NC}\n" "Rutas:" "api/http/routers/"
    printf "  %-12s ${BOLD}http://localhost:${TRAEFIK_PORT}/%-20s${NC}\n" "Servicios:" "api/http/services/"
    printf "  %-12s ${BOLD}http://localhost:${TRAEFIK_PORT}/%-20s${NC}\n" "Raw Data:" "api/rawdata"

    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

update_ssl_certificates() {
    echo "Updating SSL certificates ..."
    pushd ./traefik/certs/ > /dev/null || exit 1
    ./generate_mkcert.sh
    popd > /dev/null || exit 1
}

update_hosts_file() {
    echo "Updating local hosts file with service domains ..."
    ./common/localhost/update-hosts.sh
}

show_logs() {
    echo "Showing Docker logs in real time. Press Ctrl+C to exit."
    local cmd="docker compose --env-file \"$SELECTED_ENV_FILE\""
    if [[ "$ENV_NAME" != "local" ]] && [[ -f "versions.env" ]]; then
        cmd="$cmd --env-file versions.env"
    fi
    cmd="$cmd -f \"$COMPOSE_FILE\" logs -f"
    eval "$cmd"
}

run_config_generator() {
    echo "🔄 Generating configuration files for environment: $SELECTED_ENV_FILE"

    local generator="./common/env_vars/run-config-generator.sh"
    if [ ! -f "$generator" ]; then
        echo "❌ No se encontró el script generador en $generator"
        exit 1
    fi
    if [ ! -x "$generator" ]; then
        echo "❌ El script generador no es ejecutable. Ejecuta: chmod +x $generator"
        exit 1
    fi

    if [ ! -f "./common/env_vars/project.env-vars" ]; then
        echo "❌ No se encontró ./common/env_vars/project.env-vars"
        exit 1
    fi
    if [ ! -d "./common/env_vars/templates" ]; then
        echo "❌ No se encontró el directorio ./common/env_vars/templates"
        exit 1
    fi

    mkdir -p ./common/env_vars/generated

    "$generator" \
        "./common/env_vars/project.env-vars" \
        "./common/env_vars/generated" \
        "./common/env_vars/templates" \
        "$SELECTED_ENV_FILE" \
        ${SELECTED_ENV_VERSION_FILE:+$SELECTED_ENV_VERSION_FILE}

    if [ $? -ne 0 ]; then
        echo "❌ Config generator failed"
        exit 1
    fi
}

build_dashboard_images() {
    local stages=("$@")
    if [ ${#stages[@]} -eq 0 ]; then
        echo "❌ No stages specified"
        return 1
    fi

    local dockerfile="${DASHBOARD_PATH}/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        echo "❌ Dockerfile not found at $dockerfile"
        return 1
    fi

    local uid="${USER_UID:-1000}"
    local app_version="${DASHBOARD_VERSION:-latest}"
    local context="${DASHBOARD_PATH}"  # Contexto raíz

    # Valores del registro (desde .env.{environment})
    local registry_url="${REGISTRY_URL:-localhost:5000}"
    local registry_namespace="${REGISTRY_NAMESPACE:-minasa}"
    local registry_base="${registry_url}/${registry_namespace}"

    echo -e "${BLUE}📦 Usando versión: ${app_version}${NC}"
    echo -e "${BLUE}📦 Registro: ${registry_base}${NC}"

    local push_images=false
    read -p "Do you want to push images to registry? (y/n): " push_confirm
    if [[ "$push_confirm" =~ ^[yY]$ ]]; then
        push_images=true
    fi

    for stage in "${stages[@]}"; do
        local base_image_name=""
        local build_args="--build-arg uid=${uid} --build-arg RELEASE_TAG=${app_version}"
        local image_tag=""
        local additional_tags=()

        case "$stage" in
            production-web)
                base_image_name="pyc-dashboard-web"
                build_args="$build_args"
                image_tag="${app_version}"
                additional_tags=("latest")
                ;;
            production-worker)
                base_image_name="pyc-dashboard-worker"
                build_args="$build_args"
                image_tag="${app_version}"
                additional_tags=("latest")
                ;;
            ci)
                base_image_name="pyc-dashboard-ci"
                build_args="$build_args --build-arg user=ci_user"
                image_tag="${app_version}"
                additional_tags=("latest")
                ;;
            *)
                echo "❌ Unknown stage: $stage"
                return 1
                ;;
        esac

        # --- CONSTRUCCIÓN DIRECTA CON NOMBRE COMPLETO ---
        local full_image_name="${registry_base}/${base_image_name}:${image_tag}"

        echo -e "${YELLOW}🔨 Building $stage as ${full_image_name}...${NC}"

        docker build -f "$dockerfile" --debug \
            --target "$stage" \
            -t "$full_image_name" \
            $build_args \
            "$context"

        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Failed to build $stage${NC}"
            return 1
        else
            echo -e "${GREEN}✅ Successfully built ${full_image_name}${NC}"
        fi

        # --- TAGS ADICIONALES ---
        for tag in "${additional_tags[@]}"; do
            if [ "$tag" != "$image_tag" ]; then
                local extra_tag="${registry_base}/${base_image_name}:${tag}"
                docker tag "$full_image_name" "$extra_tag"
                echo -e "${GREEN}   Tagged as ${extra_tag}${NC}"
            fi
        done

        # --- PUSH AL REGISTRO ---
        if [ "$push_images" = true ]; then
            echo -e "${YELLOW}📤 Pushing ${full_image_name}...${NC}"
            docker push "$full_image_name"

            for tag in "${additional_tags[@]}"; do
                if [ "$tag" != "$image_tag" ]; then
                    local extra_push_tag="${registry_base}/${base_image_name}:${tag}"
                    echo -e "${YELLOW}📤 Pushing ${extra_push_tag}...${NC}"
                    docker push "$extra_push_tag"
                fi
            done

            echo -e "${GREEN}✅ Push completed for $stage${NC}"
        fi
    done

    # Resumen final
    echo -e "\n${GREEN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ BUILD COMPLETADO${NC}"
    echo -e "${BLUE}📦 Registry: ${registry_base}${NC}"
    echo -e "${BLUE}📦 Versión: ${app_version}${NC}"
}

add_local_docker_registry() {
    ./common/localhost/configure-docker-registry-in-hosts.sh && \
    ./common/localhost/configure-docker-client.sh
}

update_service_noninteractive() {
    local service="$1"
    local with_migrate="$2"  # "true" o "false"

    if [[ "$service" == "dashboard" ]] && [[ "$with_migrate" == "true" ]]; then
        echo "📦 Ejecutando migraciones con la nueva imagen..."
        docker_compose pull "$service"
        docker_compose run --rm --entrypoint php "$service" artisan migrate --force
        if [ $? -ne 0 ]; then
            echo "❌ Error al ejecutar migraciones. Abortando actualización."
            return 1
        fi
    fi

    docker_compose pull "$service"
    docker_compose up -d --no-deps --force-recreate "$service"
    echo "✅ Servicio $service actualizado con la versión actual."
}

update_service_interactive() {
    echo -e "\nServicios activos:"
    docker_compose ps --format "{{.Service}}"
    while true; do
        read -p "Nombre del servicio a actualizar (o 'q' para cancelar): " service
        if [[ "$service" == "q" ]]; then
            echo "Operación cancelada."
            exit 0
        fi
        if [[ -z "$service" ]]; then
            echo "❌ Error: No ingresaste ningún servicio. Intenta de nuevo."
            continue
        fi

        if ! docker_compose ps --format "{{.Service}}" | grep -q "^$service$"; then
            echo "❌ Error: El servicio '$service' no está activo o no existe."
            continue
        fi
        break
    done

    if [[ "$service" == "dashboard" ]]; then
        echo -n "¿Ejecutar migraciones antes de actualizar? (y/n): "
        read -r run_migrations
        migrate_flag=false
        if [[ "$run_migrations" =~ ^[yY]$ ]]; then
            migrate_flag=true
        fi
    else
        migrate_flag=false
    fi

    update_service_noninteractive "$service" "$migrate_flag"
}

rollback_service_noninteractive() {
    local service="$1"
    local target_version="$2"
    local steps="${3:-0}"   # número de migraciones a revertir, por defecto 0

    echo "🔄 Realizando rollback del servicio $service..."

    # Verificar que el servicio tenga mapeo
    local var_name="${SERVICE_VERSION_VAR[$service]}"
    if [ -z "$var_name" ]; then
        echo "❌ Servicio '$service' no tiene variable de versión asociada."
        return 1
    fi

    # Determinar archivo de versiones según entorno
    local versions_file
    if [[ "$ENV_NAME" == "production" ]]; then
        versions_file="versions.production.env"
    elif [[ "$ENV_NAME" == "uat" ]]; then
        versions_file="versions.uat.env"
    else
        echo "❌ Entorno '$ENV_NAME' no soportado para rollback."
        return 1
    fi

    # Obtener la versión actual desde el archivo (en el repositorio local)
    if [ ! -f "$versions_file" ]; then
        echo "❌ Archivo $versions_file no encontrado."
        return 1
    fi
    local current_version
    current_version=$(grep "^${var_name}=" "$versions_file" | cut -d= -f2)
    if [ -z "$current_version" ]; then
        echo "❌ No se pudo obtener la versión actual de $var_name en $versions_file."
        return 1
    fi
    echo "📦 Versión actual de $service: $current_version"

    # Si no se pasó target_version, pedirla interactivamente
    if [ -z "$target_version" ]; then
        read -p "Ingresa la versión objetivo (ej. v1.2.2): " target_version
    fi

    # Validar que la versión exista en el registry
    # Construir nombre de imagen según el servicio
    local image_name
    case "$service" in
        dashboard|dashboard_worker)
            image_name="${REGISTRY}/${NAMESPACE}/pyc-dashboard-web:${target_version}"
            ;;
        public-web)
            image_name="${REGISTRY}/${NAMESPACE}/public-web:${target_version}"
            ;;
        *)
            echo "❌ Servicio $service no tiene imagen asociada conocida."
            return 1
    esac

    echo "🔍 Verificando existencia de $image_name..."
    if ! docker manifest inspect "$image_name" > /dev/null 2>&1; then
        echo "❌ La imagen $target_version no existe en el registry. Rollback abortado."
        return 1
    fi

    # --- Revertir migraciones si es dashboard y steps > 0 ---
    if [[ "$service" == "dashboard" ]] && [ "$steps" -gt 0 ]; then
        echo "📦 Revirtiendo $steps migraciones..."
        docker_compose run --rm --entrypoint php "$service" artisan migrate:rollback --step="$steps"
        if [ $? -ne 0 ]; then
            echo "❌ Error al revertir migraciones. Rollback abortado."
            return 1
        fi
    fi

    # --- Actualizar archivo de versiones ---
    echo "🔄 Actualizando $versions_file con $var_name=$target_version..."
    # Usar sed con delimitador '|' para evitar problemas con slashes
    sed -i "s|^${var_name}=.*|${var_name}=${target_version}|" "$versions_file"
    git add "$versions_file"
    git commit -m "Rollback $service to $target_version (steps=$steps)" || echo "No changes"
    git pull --rebase origin main
    git push

    # --- Recrear el servicio ---
    echo "🚀 Actualizando servicio $service con la imagen $target_version..."
    docker_compose pull "$service"
    docker_compose up -d --no-deps --force-recreate "$service"

    echo "✅ Rollback completado. Servicio $service ahora en $target_version."
}
