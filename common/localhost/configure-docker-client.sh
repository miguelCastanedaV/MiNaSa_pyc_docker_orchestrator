#!/bin/bash
# configure-docker-client.sh
# Script para configurar clientes Docker para acceso a registro privado

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuración por defecto (puede sobrescribirse con variables de entorno)
# Formato 1: Variables individuales
REGISTRY_IP="${REGISTRY_IP:-192.168.1.100}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_HOSTNAME="${REGISTRY_HOSTNAME:-docker-registry.local}"
REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-minasa}"

# Formato 2: URL completa (sobrescribe las anteriores si está definida)
REGISTRY_URL="${REGISTRY_URL:-}"

# Determinar la URL del registro
if [ -n "$REGISTRY_URL" ]; then
    # Si se proporciona URL completa, extraer componentes (opcional)
    REGISTRY_BASE="$REGISTRY_URL"
    echo -e "${BLUE}ℹ️ Usando URL completa: $REGISTRY_BASE${NC}"
else
    # Construir desde componentes
    REGISTRY_BASE="${REGISTRY_IP}:${REGISTRY_PORT}"
    echo -e "${BLUE}ℹ️ Usando IP/puerto: $REGISTRY_BASE${NC}"
    echo -e "${BLUE}ℹ️ Hostname alternativo: $REGISTRY_HOSTNAME:$REGISTRY_PORT${NC}"
fi

# URL completa con namespace
FULL_REGISTRY="${REGISTRY_BASE}/${REGISTRY_NAMESPACE}"

echo -e "${GREEN}╭────────────────────────────────────────────╮${NC}"
echo -e "${GREEN}│   🐳 Configuración de Cliente Docker       │${NC}"
echo -e "${GREEN}╰────────────────────────────────────────────╯${NC}"
echo ""
echo -e "📦 Registry base: ${YELLOW}$REGISTRY_BASE${NC}"
echo -e "📂 Namespace: ${YELLOW}$REGISTRY_NAMESPACE${NC}"
echo -e "🔗 URL completa: ${YELLOW}$FULL_REGISTRY${NC}"
echo ""

# Función para detectar el sistema operativo
detect_os() {
    case "$OSTYPE" in
        linux-gnu*)      echo "linux" ;;
        darwin*)         echo "macos" ;;
        cygwin*|msys*)   echo "windows" ;;
        *)               echo "unknown" ;;
    esac
}

# Función para Linux
configure_linux() {
    local CONFIG_FILE="/etc/docker/daemon.json"

    echo -e "${BLUE}🔧 Configurando para Linux...${NC}"

    # Configurar Docker
    echo -e "\n${YELLOW}Configurando registros inseguros en Docker...${NC}"

    # Preparar lista de registros inseguros como array JSON válido
    local INSECURE_REPOS=()

    # Añadir el primer registro (siempre existe)
    INSECURE_REPOS+=("\"$REGISTRY_BASE\"")

    # Añadir el hostname si es diferente
    if [ -n "$REGISTRY_HOSTNAME" ] && [ "$REGISTRY_HOSTNAME" != "$REGISTRY_IP" ]; then
        INSECURE_REPOS+=("\"$REGISTRY_HOSTNAME:$REGISTRY_PORT\"")
    fi

    # Construir el array JSON manualmente para evitar problemas con comas
    local INSECURE_ARRAY=""
    local total=${#INSECURE_REPOS[@]}
    local i=0

    for repo in "${INSECURE_REPOS[@]}"; do
        INSECURE_ARRAY+="$repo"
        i=$((i + 1))
        if [ $i -lt $total ]; then
            INSECURE_ARRAY+=", "
        fi
    done

    # Encerrar entre corchetes
    INSECURE_ARRAY="[$INSECURE_ARRAY]"

    echo -e "${BLUE}📋 Registros a configurar: $INSECURE_ARRAY${NC}"

    if [ -f "$CONFIG_FILE" ]; then
        # Backup
        sudo cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

        # Usar jq si está disponible
        if command -v jq &> /dev/null; then
            local temp_file=$(mktemp)

            # Verificar si el archivo tiene contenido válido
            if [ -s "$CONFIG_FILE" ]; then
                # Verificar si el JSON actual es válido
                if jq empty "$CONFIG_FILE" 2>/dev/null; then
                    # Verificar si existe insecure-registries
                    if jq -e 'has("insecure-registries")' "$CONFIG_FILE" > /dev/null 2>&1; then
                        # Si existe, combinar arrays correctamente
                        jq --argjson new "$INSECURE_ARRAY" \
                           '.["insecure-registries"] = ((.["insecure-registries"] // []) + $new | unique)' \
                           "$CONFIG_FILE" > "$temp_file"
                    else
                        # Si no existe, crear nueva propiedad
                        jq --argjson new "$INSECURE_ARRAY" \
                           '. + {"insecure-registries": $new}' \
                           "$CONFIG_FILE" > "$temp_file"
                    fi
                else
                    # JSON actual es inválido, crear nuevo
                    echo "{ \"insecure-registries\": $INSECURE_ARRAY }" | jq '.' > "$temp_file"
                fi
            else
                # Archivo vacío, crear nuevo
                echo "{ \"insecure-registries\": $INSECURE_ARRAY }" | jq '.' > "$temp_file"
            fi

            # Verificar que el JSON generado sea válido
            if jq empty "$temp_file" 2>/dev/null; then
                sudo mv "$temp_file" "$CONFIG_FILE"
                echo -e "${GREEN}✅ Configuración actualizada correctamente${NC}"

                # Mostrar la configuración resultante
                echo -e "${BLUE}📋 Configuración actual:${NC}"
                cat "$CONFIG_FILE" | jq '.'
            else
                echo -e "${RED}❌ Error: JSON generado no es válido${NC}"
                echo -e "Contenido del archivo temporal:"
                cat "$temp_file"
                rm -f "$temp_file"
                return 1
            fi
        else
            echo -e "${RED}❌ jq no está instalado. Por favor, instala jq o edita manualmente:${NC}"
            echo "sudo nano $CONFIG_FILE"
            echo ""
            echo "Contenido recomendado:"
            echo "{"
            echo "  \"insecure-registries\": $INSECURE_ARRAY"
            echo "}"

            # Preguntar si quiere instalar jq
            echo -e "\n${YELLOW}¿Quieres instalar jq ahora? (s/n)${NC}"
            read -r install_jq
            if [[ "$install_jq" =~ ^[sS]$ ]]; then
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get install -y jq
                elif command -v yum &> /dev/null; then
                    sudo yum install -y jq
                else
                    echo -e "${RED}❌ No se pudo instalar jq automáticamente${NC}"
                fi
                # Re-ejecutar configuración
                configure_linux
                return
            fi
        fi
    else
        # Crear archivo nuevo
        echo "{ \"insecure-registries\": $INSECURE_ARRAY }" | sudo tee "$CONFIG_FILE" > /dev/null
        echo -e "${GREEN}✅ Archivo de configuración creado${NC}"
    fi

    # Reiniciar Docker
    echo -e "\n${YELLOW}Reiniciando Docker...${NC}"
    if command -v systemctl &> /dev/null; then
        sudo systemctl restart docker
    elif command -v service &> /dev/null; then
        sudo service docker restart
    else
        echo -e "${YELLOW}⚠️  Por favor, reinicia Docker manualmente${NC}"
    fi

    echo -e "${GREEN}✅ Configuración completada${NC}"
}

# Función para macOS
configure_macos() {
    echo -e "${BLUE}🍎 Configurando para macOS...${NC}"
    echo ""
    echo -e "${YELLOW}Por favor, sigue estos pasos manualmente:${NC}"
    echo ""

    echo "1. Abre Docker Desktop y ve a:"
    echo "   Settings → Docker Engine"
    echo ""
    echo "2. Modifica el JSON para incluir:"
    echo "   ${GREEN}\"insecure-registries\": [\"$REGISTRY_BASE\"${NC}"
    if [ -n "$REGISTRY_HOSTNAME" ] && [ "$REGISTRY_HOSTNAME" != "$REGISTRY_IP" ]; then
        echo "                        ${GREEN}, \"$REGISTRY_HOSTNAME:$REGISTRY_PORT\"${NC}"
    fi
    echo "                       ${GREEN}]${NC}"
    echo ""
    echo "3. Haz clic en 'Apply & Restart'"
}

# Función para Windows
configure_windows() {
    echo -e "${BLUE}🪟 Configurando para Windows...${NC}"
    echo ""
    echo -e "${YELLOW}Por favor, sigue estos pasos manualmente:${NC}"
    echo ""

    echo "1. Abre Docker Desktop y ve a:"
    echo "   Settings → Docker Engine"
    echo ""
    echo "2. Modifica el JSON para incluir:"
    echo "   ${GREEN}\"insecure-registries\": [\"$REGISTRY_BASE\"${NC}"
    if [ -n "$REGISTRY_HOSTNAME" ] && [ "$REGISTRY_HOSTNAME" != "$REGISTRY_IP" ]; then
        echo "                        ${GREEN}, \"$REGISTRY_HOSTNAME:$REGISTRY_PORT\"${NC}"
    fi
    echo "                       ${GREEN}]${NC}"
    echo ""
    echo "3. Haz clic en 'Apply & Restart'"
}

# Función para probar la conexión
test_connection() {
    echo -e "\n${BLUE}🔍 Probando conexión al registro...${NC}"

    # Probar con la IP/puerto
    if curl -s -o /dev/null -w "%{http_code}" "http://${REGISTRY_BASE}/v2/" | grep -q "200\|401"; then
        echo -e "${GREEN}✅ Conexión exitosa a $REGISTRY_BASE${NC}"
    else
        echo -e "${RED}❌ No se puede conectar a $REGISTRY_BASE${NC}"
        echo -e "   Verifica:"
        echo -e "   - Que el registro esté corriendo"
        echo -e "   - Que el firewall permita el puerto $REGISTRY_PORT"
        echo -e "   - La IP $REGISTRY_IP es correcta"
    fi

    # Probar con hostname si es diferente
    if [ -n "$REGISTRY_HOSTNAME" ] && [ "$REGISTRY_HOSTNAME" != "$REGISTRY_IP" ]; then
        if curl -s -o /dev/null -w "%{http_code}" "http://${REGISTRY_HOSTNAME}:${REGISTRY_PORT}/v2/" | grep -q "200\|401"; then
            echo -e "${GREEN}✅ Conexión exitosa a $REGISTRY_HOSTNAME:$REGISTRY_PORT${NC}"
        else
            echo -e "${RED}❌ No se puede conectar a $REGISTRY_HOSTNAME:$REGISTRY_PORT${NC}"
        fi
    fi
}

# Mostrar instrucciones finales
show_instructions() {
    echo -e "\n${GREEN}╭─────────────────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}│           🚀 INSTRUCCIONES DE USO                   │${NC}"
    echo -e "${GREEN}╰─────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "${YELLOW}Para hacer login:${NC}"
    echo "  docker login $REGISTRY_BASE"
    echo "  (si el registro requiere autenticación)"
    echo ""
    echo -e "${YELLOW}Para probar pull:${NC}"
    echo "  docker pull $FULL_REGISTRY/pyc-dashboard-web:latest"
    echo "  docker pull $FULL_REGISTRY/pyc-dashboard-worker:v1.0.0"
    echo ""
    echo -e "${YELLOW}Para usar en docker-compose.yml:${NC}"
    echo "  services:"
    echo "    pyc-dashboard:"
    echo "      image: \${REGISTRY_URL:-$FULL_REGISTRY}/pyc-dashboard-web:\${APP_VERSION:-latest}"
    echo ""
    echo -e "${YELLOW}Variables de entorno recomendadas:${NC}"
    echo "  export REGISTRY_URL=$REGISTRY_BASE"
    echo "  export REGISTRY_NAMESPACE=$REGISTRY_NAMESPACE"
    echo "  export IMAGE_WEB=\${REGISTRY_URL}/\${REGISTRY_NAMESPACE}/pyc-dashboard-web"
    echo "  export IMAGE_WORKER=\${REGISTRY_URL}/\${REGISTRY_NAMESPACE}/pyc-dashboard-worker"
}

# Ejecución principal
main() {
    OS=$(detect_os)

    case $OS in
        linux)
            configure_linux
            ;;
        macos)
            configure_macos
            ;;
        windows)
            configure_windows
            ;;
        *)
            echo -e "${RED}❌ Sistema operativo no soportado: $OSTYPE${NC}"
            exit 1
            ;;
    esac

    test_connection
    show_instructions
}

# Ejecutar función principal
main
