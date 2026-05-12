#!/bin/bash

DOMAIN=$BASE_URL # Debe estar definida en el entorno (ej: .env)
TRAEFIK_CERTS_DIR="$PWD"

# Detectar sistema operativo
OS="$(uname -s)"

install_mkcert_linux() {
  echo "⚡ Instalando dependencias para Linux..."
  sudo apt-get update
  sudo apt-get install -y libnss3-tools wget

  echo "⚡ Instalando mkcert..."
  wget -O mkcert https://dl.filippo.io/mkcert/latest?for=linux/amd64
  chmod +x mkcert
  sudo mv mkcert /usr/local/bin/mkcert
}

install_mkcert_macos() {
  echo "⚡ Instalando mkcert en macOS..."
  if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew no está instalado. Instálalo primero: https://brew.sh"
    exit 1
  fi
  brew install mkcert nss
}

install_mkcert_windows() {
  echo "⚡ Detectado Windows (Git Bash / WSL)."
  echo "Por favor instala mkcert con Chocolatey:"
  echo "   choco install mkcert"
  exit 1
}

# Verificar si mkcert está instalado
if ! command -v mkcert &>/dev/null; then
  echo "⚡ mkcert no está instalado. Instalando..."

  case "$OS" in
    Linux*)   install_mkcert_linux ;;
    Darwin*)  install_mkcert_macos ;;
    CYGWIN*|MINGW*|MSYS*) install_mkcert_windows ;;
    *) echo "❌ Sistema operativo no soportado: $OS"; exit 1 ;;
  esac
else
  echo "✅ mkcert ya está instalado."
fi

# Inicializar CA si no existe
echo "⚡ Configurando CA local con mkcert..."
mkcert -install

# Generar certificados
echo "⚡ Generando certificados para $DOMAIN y *.$DOMAIN ..."
mkcert "$DOMAIN" "*.$DOMAIN"

echo "✅ Certificados generados en el directorio actual."


# Copiar la CA raíz de mkcert (CRÍTICO)
echo "🔑 Copiando CA raíz de mkcert..."

# Buscar la CA raíz de mkcert en las ubicaciones comunes
find_mkcert_root_ca() {
  local found_path=""

  case "$OS" in
    Linux*)
      # Ubuntu/Debian Linux
      local paths=(
        "$HOME/.local/share/mkcert/rootCA.pem"
        "$HOME/.local/share/mkcert/rootCA-key.pem"
        "/root/.local/share/mkcert/rootCA.pem"
        "/usr/local/share/ca-certificates/rootCA.pem"
      )
      ;;
    Darwin*)
      # macOS
      local paths=(
        "$HOME/Library/Application Support/mkcert/rootCA.pem"
        "$HOME/Library/Application Support/mkcert/rootCA-key.pem"
        "/Library/Application Support/mkcert/rootCA.pem"
      )
      ;;
  esac

  for path in "${paths[@]}"; do
    if [ -f "$path" ]; then
      found_path="$path"
      break
    fi
  done

  # Si no se encontró en las rutas comunes, buscar recursivamente
  if [ -z "$found_path" ]; then
    echo "   🔍 Buscando CA raíz recursivamente..."
    if [ "$OS" = "Linux" ]; then
      found_path=$(find /home /root -name "rootCA.pem" 2>/dev/null | head -1)
    elif [ "$OS" = "Darwin" ]; then
      found_path=$(find ~ -name "rootCA.pem" 2>/dev/null | head -1)
    fi
  fi

  echo "$found_path"
}

MKCERT_ROOT_CA=$(find_mkcert_root_ca)

if [ -n "$MKCERT_ROOT_CA" ] && [ -f "$MKCERT_ROOT_CA" ]; then
  echo "   ✅ CA raíz encontrada: $MKCERT_ROOT_CA"

  # Copiar la CA raíz
  cp "$MKCERT_ROOT_CA" "$TRAEFIK_CERTS_DIR/mkcert-rootCA.pem"
  echo "   ✅ CA raíz copiada a: $TRAEFIK_CERTS_DIR/mkcert-rootCA.pem"

  # Verificar que es una CA válida
  echo "   🔍 Validando CA raíz..."
  if openssl x509 -in "$TRAEFIK_CERTS_DIR/mkcert-rootCA.pem" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
    echo "   ✅ La CA raíz tiene CA:TRUE (válida para verificar certificados)"
  else
    echo "   ⚠️  Advertencia: La CA raíz podría no tener CA:TRUE"
    echo "   Verificando manualmente..."
    openssl x509 -in "$TRAEFIK_CERTS_DIR/mkcert-rootCA.pem" -noout -subject -issuer 2>/dev/null | sed 's/^/      /'
  fi

  # 4. Crear archivo de cadena completa (certificado leaf + CA raíz)
  echo "🔗 Creando cadena completa de certificados..."
  if [ -f "$TRAEFIK_CERTS_DIR/${DOMAIN}+1.pem" ] && [ -f "$TRAEFIK_CERTS_DIR/mkcert-rootCA.pem" ]; then
    cat "$TRAEFIK_CERTS_DIR/${DOMAIN}+1.pem" "$TRAEFIK_CERTS_DIR/mkcert-rootCA.pem" > "$TRAEFIK_CERTS_DIR/${DOMAIN}+1-fullchain.pem"
    echo "   ✅ Cadena completa creada: ${DOMAIN}+1-fullchain.pem"
  fi

  # 5. Crear un bundle de CA para PHP (opcional)
  echo "📦 Creando bundle de CA para PHP..."
  cat "$TRAEFIK_CERTS_DIR/mkcert-rootCA.pem" > "$TRAEFIK_CERTS_DIR/ca-bundle.crt"

  # Agregar otras CA del sistema si es necesario
  if [ -f "/etc/ssl/certs/ca-certificates.crt" ]; then
    cat "/etc/ssl/certs/ca-certificates.crt" >> "$TRAEFIK_CERTS_DIR/ca-bundle.crt"
  fi

else
  echo "   ❌ ERROR: No se encontró la CA raíz de mkcert"
  echo "   Posibles soluciones:"
  echo "   1. Ejecuta 'mkcert -install' manualmente"
  echo "   2. Busca la CA raíz con: find ~ -name 'rootCA.pem'"
  echo "   3. La CA raíz podría estar en:"
  echo "      - Linux: ~/.local/share/mkcert/rootCA.pem"
  echo "      - macOS: ~/Library/Application Support/mkcert/rootCA.pem"
  exit 1
fi

# 6. Verificar permisos
echo "🔒 Ajustando permisos..."
chmod 644 "$TRAEFIK_CERTS_DIR"/*.pem 2>/dev/null || true
chmod 644 "$TRAEFIK_CERTS_DIR"/*.crt 2>/dev/null || true
chmod 600 "$TRAEFIK_CERTS_DIR"/*-key.pem 2>/dev/null || true

echo ""
echo "🎉 PROCESO COMPLETADO EXITOSAMENTE!"
echo ""
