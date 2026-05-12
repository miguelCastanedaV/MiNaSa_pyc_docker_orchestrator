#!/bin/bash
set -e

IMAGE_NAME="config-generator:latest"
DOCKERFILE_DIR="$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

usage() {
    echo "Uso: $0 <archivo_variables> <directorio_salida> <directorio_plantillas> [archivo_env_compose1] [archivo_env_compose2] ..."
    echo ""
    echo "Ejemplos:"
    echo "  $0 ./project.env-vars ./generated ./templates"
    echo "  $0 ./project.env-vars ./generated ./templates ../.env"
    echo "  $0 ./project.env-vars ./generated ./templates ../.env ../.env.production"
    exit 1
}

if [ $# -lt 3 ]; then
    usage
fi

VARS_FILE=$(realpath "$1")
OUTPUT_DIR=$(realpath "$2")
TEMPLATES_DIR=$(realpath "$3")
shift 3  # Eliminar los primeros 3 argumentos

# Construir opciones --env-file para los archivos adicionales
ENV_FILE_OPTS=""
COMPOSE_ENV_FILES=()
for env_file in "$@"; do
    if [ -f "$env_file" ]; then
        ENV_FILE_OPTS="$ENV_FILE_OPTS --env-file $(realpath "$env_file")"
        COMPOSE_ENV_FILES+=("$(realpath "$env_file")")
    else
        echo -e "${RED}❌ Archivo env compose no existe: $env_file${NC}"
        exit 1
    fi
done

[ ! -f "$VARS_FILE" ] && { echo -e "${RED}❌ Archivo variables no existe${NC}"; exit 1; }
[ ! -d "$TEMPLATES_DIR" ] && { echo -e "${RED}❌ Directorio plantillas no existe${NC}"; exit 1; }
mkdir -p "$OUTPUT_DIR"

HOST_UID=$(id -u)
HOST_GID=$(id -g)

echo -e "${YELLOW}🔨 Construyendo imagen...${NC}"
docker build -t "$IMAGE_NAME" "$DOCKERFILE_DIR"

echo -e "${YELLOW}🚀 Generando configuraciones...${NC}"
echo "   Archivo variables : $VARS_FILE"
echo "   Directorio salida  : $OUTPUT_DIR"
echo "   Plantillas         : $TEMPLATES_DIR"
if [ ${#COMPOSE_ENV_FILES[@]} -gt 0 ]; then
    echo "   Archivos env compose:"
    for f in "${COMPOSE_ENV_FILES[@]}"; do
        echo "     - $f"
    done
fi

# Ejecutar docker con todos los --env-file
docker run --rm \
    $ENV_FILE_OPTS \
    -v "$VARS_FILE:/input/vars.env:ro" \
    -v "$OUTPUT_DIR:/output" \
    -v "$TEMPLATES_DIR:/templates:ro" \
    -e HOST_UID="$HOST_UID" \
    -e HOST_GID="$HOST_GID" \
    "$IMAGE_NAME" \
    /input/vars.env /output /templates

echo -e "${GREEN}✅ Archivos generados en:${NC}"
ls -l "$OUTPUT_DIR"
