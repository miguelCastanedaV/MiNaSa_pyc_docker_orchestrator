#!/bin/bash
set -e

if [ $# -ne 3 ]; then
    echo "Uso: $0 <archivo_variables> <directorio_salida> <directorio_plantillas>"
    exit 1
fi

VARS_FILE="$1"
OUTPUT_DIR="$2"
TEMPLATES_DIR="$3"

# Verificar existencia
for d in "$VARS_FILE" "$OUTPUT_DIR" "$TEMPLATES_DIR"; do
    if [ ! -e "$d" ]; then
        echo "Error: No existe: $d"
        exit 1
    fi
done

# Paso 1: Extraer variables base y exportarlas
in_base_section=0
base_lines=()
while IFS= read -r line || [ -n "$line" ]; do
    # Detectar inicio de sección BASE
    if [[ "$line" =~ ^[[:space:]]*#+[[:space:]]*BASE[[:space:]]+VARIABLES[[:space:]]*#+ ]]; then
        in_base_section=1
        continue
    fi
    # Detectar fin de sección BASE
    if [[ "$line" =~ ^[[:space:]]*#+[[:space:]]*END[[:space:]]+BASE[[:space:]]+VARIABLES[[:space:]]*#+ ]]; then
        in_base_section=0
        continue
    fi

    if [ $in_base_section -eq 1 ]; then
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            base_lines+=("$line")
            # Extraer clave y valor para exportar
            if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                export "$key=$value"
            fi
        fi
    fi
done < "$VARS_FILE"

# Paso 2: Crear archivo temporal con todas las variables (base + prefijadas) expandidas
TEMP_FILE=$(mktemp)
while IFS= read -r line || [ -n "$line" ]; do
    # Ignorar líneas de marcadores de sección
    if [[ "$line" =~ ^[[:space:]]*#+.*BASE.*VARIABLES.*#+ ]]; then
        continue
    fi
    if [[ "$line" =~ ^[[:space:]]*#+.*END.*BASE.*VARIABLES.*#+ ]]; then
        continue
    fi
    # Si es una línea con clave=valor (puede tener comentario al final)
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # Expandir el valor con envsubst (usa las variables base exportadas)
        expanded=$(echo "$value" | envsubst)
        echo "$key=$expanded" >> "$TEMP_FILE"
    fi
done < "$VARS_FILE"

echo "📝 Generando archivos desde $TEMPLATES_DIR..."

APP_ENV=${APP_ENV:-production}
# Paso 3: Iterar sobre las plantillas
for template in "$TEMPLATES_DIR"/*; do
    [ ! -f "$template" ] && continue
    basename=$(basename "$template")
    output_name=$(echo "$basename" | sed 's/\.example$//')
    output_file="$OUTPUT_DIR/$APP_ENV.$output_name"
    echo "   → $basename -> $output_name"

    # Determinar prefijo a partir del nombre de salida
    service_part=$(echo "$output_name" | sed 's/\..*//' | tr '[:lower:]' '[:upper:]')
    prefix="${service_part}_"

    # Leer el archivo temporal y filtrar variables con ese prefijo
    declare -A SERVICE_VARS
    while IFS='=' read -r key value; do
        if [[ "$key" == "$prefix"* ]]; then
            new_key="${key#$prefix}"
            SERVICE_VARS["$new_key"]="$value"
        fi
    done < "$TEMP_FILE"

    # Procesar la plantilla línea por línea, reemplazando donde coincida
    declare -A SEEN_KEYS
    while IFS= read -r line; do
        if echo "$line" | grep -q '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*='; then
            key=$(echo "$line" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            SEEN_KEYS["$key"]=1
            if [ "${SERVICE_VARS[$key]+_}" ]; then
                echo "$key=${SERVICE_VARS[$key]}"
            else
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done < "$template" > "$output_file"

    # Añadir variables nuevas (del servicio) que no estaban en la plantilla
    new_vars=()
    for key in $(echo "${!SERVICE_VARS[@]}" | tr ' ' '\n' | sort); do
        if [ -z "${SEEN_KEYS[$key]}" ]; then
            new_vars+=("$key=${SERVICE_VARS[$key]}")
        fi
    done
    if [ ${#new_vars[@]} -gt 0 ]; then
        echo "" >> "$output_file"
        echo "# Variables automatically added from $VARS_FILE" >> "$output_file"
        for var in "${new_vars[@]}"; do
            echo "$var" >> "$output_file"
        done
    fi
done

# Limpiar
rm -f "$TEMP_FILE"

# Ajustar permisos si se proporcionan UID y GID
if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
    echo "🔧 Ajustando permisos a $HOST_UID:$HOST_GID en $OUTPUT_DIR"
    chown -R "$HOST_UID:$HOST_GID" "$OUTPUT_DIR"
fi

echo "✅ Archivos generados en $OUTPUT_DIR"
