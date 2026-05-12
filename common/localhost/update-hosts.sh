#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔄 Actualizando /etc/hosts con dominios de Traefik...${NC}"

# Configuración
HOSTS_FILE="/etc/hosts"
MARKER_START="# PideYCuenta DOMAINS START (${APP_ENV})"
MARKER_END="# PideYCuenta DOMAINS END (${APP_ENV})"
TRAEFIK_DYNAMIC_FILE="./traefik/traefik_dynamic.${APP_ENV}.yml"

echo -e "📁 Usando archivo: ${TRAEFIK_DYNAMIC_FILE}"

# Verificar que el archivo existe
if [ ! -f "$TRAEFIK_DYNAMIC_FILE" ]; then
    echo -e "❌ Archivo no encontrado: $TRAEFIK_DYNAMIC_FILE"
    exit 1
fi

# Crear marcadores si no existen
if ! grep -q "$MARKER_START" $HOSTS_FILE; then
    echo "" | sudo tee -a $HOSTS_FILE > /dev/null
    echo "$MARKER_START" | sudo tee -a $HOSTS_FILE > /dev/null
    echo "$MARKER_END" | sudo tee -a $HOSTS_FILE > /dev/null
    echo -e "✅ Marcadores creados en /etc/hosts"
fi

# Extraer dominios del archivo traefik_dynamic
DOMAINS=$(mktemp)

# Buscar reglas de Host en routers
grep -E "rule:.*Host" "$TRAEFIK_DYNAMIC_FILE" | \
    sed -n 's/.*Host(\([^)]*\)).*/\1/p' | \
    tr -d '`"' | \
    tr ',' '\n' | \
    sed 's/^ *//;s/ *$//' > $DOMAINS

# Ordenar y eliminar duplicados
sort -u $DOMAINS > ${DOMAINS}_sorted

# Limpiar sección anterior en /etc/hosts
sudo sed -i "/$MARKER_START/,/$MARKER_END/ { /$MARKER_START\|$MARKER_END/!d }" $HOSTS_FILE

# Generar nuevas entradas
HOSTS_ENTRIES=$(mktemp)
while read domain; do
    if [ -n "$domain" ]; then
        echo "127.0.0.1 $domain" >> $HOSTS_ENTRIES
    fi
done < ${DOMAINS}_sorted

# Insertar nuevas entradas
sudo sed -i "/$MARKER_START/r $HOSTS_ENTRIES" $HOSTS_FILE

# Limpiar archivos temporales
rm -f $DOMAINS ${DOMAINS}_sorted $HOSTS_ENTRIES

# Mostrar resultado
echo -e "${GREEN}✅ Dominios actualizados en /etc/hosts:${NC}"
grep -A 100 "$MARKER_START" $HOSTS_FILE | grep -B 100 "$MARKER_END" | grep -v "$MARKER_START\|$MARKER_END"

echo -e "${GREEN}🎯 Total de dominios: $(grep -A 100 "$MARKER_START" $HOSTS_FILE | grep -B 100 "$MARKER_END" | grep -v "$MARKER_START\|$MARKER_END" | wc -l)${NC}"
