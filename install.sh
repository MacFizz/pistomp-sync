#!/usr/bin/env bash
set -euo pipefail

# Variables d'installation
BASE_LIB="/usr/local/lib/pistomp-sync"
CONFIG_DIR="/home/pistomp/data/config"
BIN_LINK="/usr/local/bin/pistomp-sync"
STATE_DIR="/home/pistomp/data/sync/state"
LOG_FILE="/var/log/pistomp-sync.log"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== PiStomp Sync Installer ==="

# 1. Crée les répertoires nécessaires
mkdir -p "$BASE_LIB/lib"
mkdir -p "$CONFIG_DIR"
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"
chown pistomp:pistomp "$CONFIG_DIR" "$STATE_DIR" "$LOG_FILE"
chmod 755 "$BASE_LIB" "$STATE_DIR"
chmod 644 "$LOG_FILE"

# 2. Installe les scripts
install -m 755 pistomp-sync.sh "$BASE_LIB/pistomp-sync.sh"
install -m 644 lib/yaml.sh "$BASE_LIB/lib/yaml.sh"

# 3. Crée le lien exécutable
ln -sf "$BASE_LIB/pistomp-sync.sh" "$BIN_LINK"

# 4. Installe le fichier de configuration exemple si absent
if [[ ! -f "$CONFIG_DIR/sync.yml" ]]; then
    install -m 644 config/sync.yml.example "$CONFIG_DIR/sync.yml"
    chown pistomp:pistomp "$CONFIG_DIR/sync.yml"
    echo "Config installed at $CONFIG_DIR/sync.yml"
fi

# 5. Installe les services systemd
for f in systemd/pistomp-sync-boot.service \
         systemd/pistomp-sync-shutdown.service \
         systemd/pistomp-sync.service \
         systemd/pistomp-sync.timer; do
    install -m 644 "$f" "$SYSTEMD_DIR/"
done

# 6. Reload systemd
systemctl daemon-reload

# 7. Activation interactive
read -p "Activate boot service? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && systemctl enable pistomp-sync-boot.service

read -p "Activate shutdown service? [y/N]: " ans
[[ "$ans" =~ ^[Yy]$ ]] && systemctl enable pistomp-sync-shutdown.service

read -p "Activate timer service? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    read -p "Interval in minutes between syncs: " interval
    sed -i "s/^OnCalendar=.*/OnCalendar=*-*-* *:*:00/" "$SYSTEMD_DIR/pistomp-sync.timer"
    systemctl enable pistomp-sync.timer
    systemctl start pistomp-sync.timer
fi

echo "=== Installation complete ==="
echo "Config file: $CONFIG_DIR/sync.yml"
echo "Executable: $BIN_LINK"
echo "Log: $LOG_FILE"
echo "State dir: $STATE_DIR"
