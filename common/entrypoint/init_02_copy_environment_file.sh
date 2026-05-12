#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function for logging messages (redirect to stderr)

log_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${GREEN}[INFO]${NC} $1" >&2
    fi
}

log_warn() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function for final message (always displayed)
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

if [ ! -f "/tmp/dashboard.env"  ]; then
    log_error "/tmp/dashboard.env file found"
    exit 1
fi

if [ "$APP_ENV" == "worker" ]; then
  cp /tmp/dashboard.env .env.worker
  log_success "/tmp/dashboard.env file copied to .env.worker"
else
  cp /tmp/dashboard.env .env
  log_success "/tmp/dashboard.env file copied to .env"
fi
