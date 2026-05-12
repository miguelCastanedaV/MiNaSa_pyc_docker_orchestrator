#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}🔄 Actualizando /etc/hosts con dominio del Docker Registry...${NC}"

# Configuración
HOSTS_FILE="/etc/hosts"
MARKER_START="# GESTIONASIG REGISTRY START"
MARKER_END="# GESTIONASIG REGISTRY END"

# Configuración del registro - EDITAR SEGÚN TUS NECESIDADES
# ========================================================
REGISTRY_IP="${REGISTRY_IP:-127.0.0.1}"           # IP de tu servidor
REGISTRY_HOSTNAME="${REGISTRY_HOSTNAME:-docker-registry.local}"  # Hostname amigable
REGISTRY_PORT="${REGISTRY_PORT:-5000}"            # Puerto del registro
# ========================================================

echo -e "📁 Configuración del registro:"
echo -e "   IP: ${BLUE}${REGISTRY_IP}${NC}"
echo -e "   Hostname: ${BLUE}${REGISTRY_HOSTNAME}${NC}"
echo -e "   Puerto: ${BLUE}${REGISTRY_PORT}${NC}"
echo -e "   URL completa: ${BLUE}http://${REGISTRY_HOSTNAME}:${REGISTRY_PORT}${NC}"

# Crear marcadores si no existen
if ! grep -q "$MARKER_START" $HOSTS_FILE; then
    echo "" | sudo tee -a $HOSTS_FILE > /dev/null
    echo "$MARKER_START" | sudo tee -a $HOSTS_FILE > /dev/null
    echo "$MARKER_END" | sudo tee -a $HOSTS_FILE > /dev/null
    echo -e "✅ Marcadores creados en /etc/hosts"
fi

# Crear archivo temporal con la entrada
HOSTS_ENTRIES=$(mktemp)

# Generar entrada para el registro (solo hostname, el puerto no va en hosts)
echo "${REGISTRY_IP} ${REGISTRY_HOSTNAME}" >> $HOSTS_ENTRIES

# Limpiar sección anterior en /etc/hosts
sudo sed -i "/$MARKER_START/,/$MARKER_END/ { /$MARKER_START\|$MARKER_END/!d }" $HOSTS_FILE

# Insertar nuevas entradas
sudo sed -i "/$MARKER_START/r $HOSTS_ENTRIES" $HOSTS_FILE

# Limpiar archivos temporales
rm -f $HOSTS_ENTRIES

# Mostrar resultado
echo -e "${GREEN}✅ Entrada actualizada en /etc/hosts:${NC}"
grep -A 100 "$MARKER_START" $HOSTS_FILE | grep -B 100 "$MARKER_END" | grep -v "$MARKER_START\|$MARKER_END"

# Verificar resolución DNS
echo -e "\n${YELLOW}🔍 Verificando resolución de nombres...${NC}"
if ping -c 1 "$REGISTRY_HOSTNAME" &> /dev/null; then
    echo -e "${GREEN}✅ $REGISTRY_HOSTNAME resuelve correctamente${NC}"
else
    echo -e "${RED}❌ $REGISTRY_HOSTNAME no resuelve${NC}"
fi

echo -e "\n${GREEN}🎯 Registro configurado: ${REGISTRY_HOSTNAME}:${REGISTRY_PORT} -> ${REGISTRY_IP}${NC}"
echo -e "${BLUE}📦 Comandos útiles:${NC}"
echo "   # Verificar conectividad con el registro"
echo "   curl http://${REGISTRY_HOSTNAME}:${REGISTRY_PORT}/v2/_catalog"
echo ""
echo "   # Hacer pull de una imagen"
echo "   docker pull ${REGISTRY_HOSTNAME}:${REGISTRY_PORT}/gestionasig/gs-phva-web:latest"
echo ""
echo "   # Configurar Docker para registro inseguro (si es HTTP)"
echo "   # Añadir a /etc/docker/daemon.json:"
echo "   {"
echo "     \"insecure-registries\": [\"${REGISTRY_HOSTNAME}:${REGISTRY_PORT}\"]"
echo "   }"
