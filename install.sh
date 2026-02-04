#!/usr/bin/env bash
set -e

APP_NAME="pistomp-sync"
INSTALL_DIR="/usr/local/lib/${APP_NAME}"
SYSTEMD_DIR="/etc/systemd/system"
USER_NAME="pistomp"

echo "=== Déploiement ${APP_NAME} ==="
echo

if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être lancé avec sudo"
  exit 1
fi

# -----------------------------
# 1. Installation des fichiers
# -----------------------------
echo "📁 Installation dans ${INSTALL_DIR}"

mkdir -p "${INSTALL_DIR}"
cp -r pistomp-sync.sh config systemd "${INSTALL_DIR}/"

chmod +x "${INSTALL_DIR}/pistomp-sync.sh"
chown -R root:root "${INSTALL_DIR}"

# -----------------------------
# 2. Création du state directory
# -----------------------------
STATE_DIR="/home/${USER_NAME}/data/sync/state"

echo "📁 Création du répertoire state : ${STATE_DIR}"
mkdir -p "${STATE_DIR}"
touch "${STATE_DIR}/.keep"
chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/data/sync"

# -----------------------------
# 3. Installation systemd units
# -----------------------------
echo "⚙️ Installation des unités systemd"

cp "${INSTALL_DIR}/systemd/"*.service "${SYSTEMD_DIR}/"
cp "${INSTALL_DIR}/systemd/"*.timer "${SYSTEMD_DIR}/"

systemctl daemon-reexec
systemctl daemon-reload

# -----------------------------
# 4. Activation interactive
# -----------------------------
echo
read -rp "👉 Activer la synchronisation au BOOT ? (y/N) " ENABLE_BOOT
if [[ "${ENABLE_BOOT}" =~ ^[Yy]$ ]]; then
  systemctl enable pistomp-sync-boot.service
  echo "✔ Service boot activé"
fi

read -rp "👉 Activer la synchronisation au SHUTDOWN ? (y/N) " ENABLE_SHUTDOWN
if [[ "${ENABLE_SHUTDOWN}" =~ ^[Yy]$ ]]; then
  systemctl enable pistomp-sync-shutdown.service
  echo "✔ Service shutdown activé"
fi

read -rp "👉 Activer la synchronisation périodique (timer) ? (y/N) " ENABLE_TIMER
if [[ "${ENABLE_TIMER}" =~ ^[Yy]$ ]]; then
  read -rp "⏱ Intervalle entre deux synchros (minutes, défaut: 30) : " INTERVAL
  INTERVAL=${INTERVAL:-30}

  TIMER_FILE="${SYSTEMD_DIR}/pistomp-sync.timer"

  sed -i "s|^OnUnitActiveSec=.*|OnUnitActiveSec=${INTERVAL}min|" "${TIMER_FILE}"

  systemctl enable pistomp-sync.timer
  systemctl start pistomp-sync.timer

  echo "✔ Timer activé (toutes les ${INTERVAL} minutes)"
fi

echo
echo "✅ Déploiement terminé"
echo "🔎 Vérification :"
echo "   systemctl list-timers pistomp-sync.timer"
echo "   journalctl -u pistomp-sync-boot.service"
