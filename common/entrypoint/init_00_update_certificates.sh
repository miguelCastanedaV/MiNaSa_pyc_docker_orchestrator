#!/bin/bash
echo "Installing mkcert root CA..."

# Fuente y destino
CA_SRC="/etc/ssl/certs/traefik/mkcert-rootCA.pem"
CA_DEST="/usr/local/share/ca-certificates/mkcert-rootCA.crt"

# Verificar que existe
if [ ! -f "$CA_SRC" ]; then
    echo "ERROR: mkcert root CA not found at $CA_SRC"
    exit 1
fi

# Copiar
sudo cp "$CA_SRC" "$CA_DEST"

# Actualizar certificados del sistema
sudo update-ca-certificates

echo "mkcert root CA installed successfully"
echo "Certificates available at:"
echo "  - /etc/ssl/certs/traefik/mkcert-rootCA.pem (direct)"
echo "  - /etc/ssl/certs/ca-certificates.crt (system bundle)"
