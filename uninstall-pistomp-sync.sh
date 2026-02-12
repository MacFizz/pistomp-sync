#!/bin/bash
# uninstall-pistomp-sync.sh - Désinstallation de pistomp-sync

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/pistomp-sync"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/pistomp-sync"
LOG_DIR="/var/log/pistomp-sync"
SERVICE_NAME="pistomp-sync"

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then
    echo_error "Ce script doit être exécuté en tant que root (sudo)"
    exit 1
fi

echo ""
echo_warning "╔═══════════════════════════════════════════════════╗"
echo_warning "║   Désinstallation de PiStomp Sync                ║"
echo_warning "╚═══════════════════════════════════════════════════╝"
echo ""

read -p "Voulez-vous vraiment désinstaller pistomp-sync ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    echo "Désinstallation annulée"
    exit 0
fi

# Arrêter et désactiver les services
echo_info "Arrêt des services..."
systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl stop "${SERVICE_NAME}-shutdown.service" 2>/dev/null || true

systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}-shutdown.service" 2>/dev/null || true

# Supprimer les fichiers de service
echo_info "Suppression des services systemd..."
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
rm -f "/etc/systemd/system/${SERVICE_NAME}.timer"
rm -f "/etc/systemd/system/${SERVICE_NAME}-shutdown.service"
systemctl daemon-reload

# Supprimer les fichiers
echo_info "Suppression des fichiers..."
rm -f "$BIN_DIR/pistomp-sync"
rm -rf "$INSTALL_DIR"
rm -f "/etc/logrotate.d/pistomp-sync"

# Demander si on supprime la configuration et les logs
read -p "Supprimer la configuration ? ($CONFIG_DIR) (o/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    rm -rf "$CONFIG_DIR"
    echo_success "Configuration supprimée"
else
    echo_warning "Configuration conservée"
fi

read -p "Supprimer les logs ? ($LOG_DIR) (o/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    rm -rf "$LOG_DIR"
    echo_success "Logs supprimés"
else
    echo_warning "Logs conservés"
fi

echo ""
echo_success "═══════════════════════════════════════════════════"
echo_success "   Désinstallation terminée"
echo_success "═══════════════════════════════════════════════════"
echo ""
