#!/bin/bash
# install-pistomp-sync.sh - Installation de pistomp-sync

set -e  # Arrêter en cas d'erreur

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/pistomp-sync"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/pistomp-sync"
USER_CONFIG_DIR="$HOME/.config"
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

# Vérifier si le script est exécuté en tant que root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_error "Ce script doit être exécuté en tant que root (sudo)"
        exit 1
    fi
}

# Obtenir l'utilisateur réel (pas root)
get_real_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

# Installer les dépendances
install_dependencies() {
    echo_info "Vérification des dépendances..."
    
    # Vérifier si rclone est installé
    if ! command -v rclone &> /dev/null; then
        echo_warning "rclone n'est pas installé"
        echo_info "Installation de rclone..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y rclone
        elif command -v yum &> /dev/null; then
            yum install -y rclone
        elif command -v pacman &> /dev/null; then
            pacman -S --noconfirm rclone
        else
            echo_error "Gestionnaire de paquets non supporté. Installez rclone manuellement."
            exit 1
        fi
    fi
    
    echo_success "rclone est installé : $(rclone version | head -1)"
}

# Créer les répertoires nécessaires
create_directories() {
    echo_info "Création des répertoires..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$USER_CONFIG_DIR"
    
    # Permissions pour les logs
    chmod 755 "$LOG_DIR"
    
    echo_success "Répertoires créés"
}

# Copier les fichiers
install_files() {
    echo_info "Installation des fichiers..."
    
    # Copier le script principal
    if [ ! -f "pistomp-sync.sh" ]; then
        echo_error "pistomp-sync.sh non trouvé dans le répertoire courant"
        exit 1
    fi
    
    cp pistomp-sync.sh "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/pistomp-sync.sh"
    
    # Créer un lien symbolique
    ln -sf "$INSTALL_DIR/pistomp-sync.sh" "$BIN_DIR/pistomp-sync"
    
    echo_success "Fichiers installés"
}

# Créer un fichier de configuration par défaut
create_default_config() {
    local real_user=$(get_real_user)
    local user_home=$(eval echo ~$real_user)
    local config_file="$CONFIG_DIR/pistomp-sync.conf"
    
    if [ -f "$config_file" ]; then
        echo_warning "Configuration existante trouvée, conservation"
        return
    fi
    
    echo_info "Création du fichier de configuration par défaut..."
    
    cat > "$config_file" << EOF
# pistomp-sync.conf
# Configuration de synchronisation bidirectionnelle

# Section pedalboards
[pedalboards]
local = $user_home/data/.pedalboards/
remote = nxt:Apps/pistomp-sync/pedalboards/
description = Pedalboards et effets
enabled = true

# Section favoris
[favoris]
local = $user_home/data/favorites.json
remote = nxt:Apps/pistomp-sync/favorites.json
description = Favoris
enabled = false

# Section banks
[banks]
local = $user_home/data/banks.json
remote = nxt:Apps/pistomp-sync/banks.json
description = Banks
enabled = false

# Section user-files
[user-files]
local = $user_home/data/user-files/
remote = nxt:Apps/pistomp-sync/user-files/
description = Fichiers utilisateur
enabled = false
EOF
    
    chmod 644 "$config_file"
    echo_success "Configuration créée : $config_file"
    echo_warning "⚠️  Pensez à éditer la configuration avant d'activer le service !"
}

# Créer le service systemd
create_systemd_service() {
    local real_user=$(get_real_user)
    local user_home=$(eval echo ~$real_user)
    
    echo_info "Création du service systemd..."
    
    # Service principal (timer)
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=PiStomp Sync - Synchronisation bidirectionnelle
After=network-online.target
Wants=network-online.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
User=$real_user
Group=$real_user
Environment="HOME=$user_home"
Environment="CONFIG_FILE=$CONFIG_DIR/pistomp-sync.conf"
ExecStart=$INSTALL_DIR/pistomp-sync.sh -c $CONFIG_DIR/pistomp-sync.conf
StandardOutput=append:$LOG_DIR/pistomp-sync.log
StandardError=append:$LOG_DIR/pistomp-sync.log
TimeoutStartSec=600
TimeoutStopSec=600

# Options de sécurité
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$LOG_DIR $user_home/.cache/rclone $user_home/data

[Install]
WantedBy=multi-user.target
EOF

    # Timer pour exécution périodique
    cat > "/etc/systemd/system/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=PiStomp Sync Timer - Synchronisation toutes les 15 minutes
Requires=${SERVICE_NAME}.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Service de synchronisation au shutdown
    cat > "/etc/systemd/system/${SERVICE_NAME}-shutdown.service" << EOF
[Unit]
Description=PiStomp Sync - Synchronisation avant arrêt
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
After=network.target

[Service]
Type=oneshot
User=$real_user
Group=$real_user
Environment="HOME=$user_home"
Environment="CONFIG_FILE=$CONFIG_DIR/pistomp-sync.conf"
ExecStart=$INSTALL_DIR/pistomp-sync.sh -c $CONFIG_DIR/pistomp-sync.conf
StandardOutput=append:$LOG_DIR/pistomp-sync.log
StandardError=append:$LOG_DIR/pistomp-sync.log
TimeoutStartSec=300
RemainAfterExit=yes

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

    # Recharger systemd
    systemctl daemon-reload
    
    echo_success "Services systemd créés"
}

# Configurer les permissions des logs
setup_log_permissions() {
    local real_user=$(get_real_user)
    
    echo_info "Configuration des permissions..."
    
    # Créer le fichier de log
    touch "$LOG_DIR/pistomp-sync.log"
    chown "$real_user:$real_user" "$LOG_DIR/pistomp-sync.log"
    chmod 644 "$LOG_DIR/pistomp-sync.log"
    
    # Configurer logrotate
    cat > "/etc/logrotate.d/pistomp-sync" << EOF
$LOG_DIR/pistomp-sync.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $real_user $real_user
}
EOF
    
    echo_success "Permissions configurées"
}

# Activer les services
enable_services() {
    echo_info "Activation des services..."
    
    read -p "Voulez-vous activer les services maintenant ? (o/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Oo]$ ]]; then
        # Activer le timer (synchronisation périodique)
        systemctl enable "${SERVICE_NAME}.timer"
        
        # Activer le service de shutdown
        systemctl enable "${SERVICE_NAME}-shutdown.service"
        
        echo_success "Services activés"
        
        read -p "Voulez-vous démarrer la synchronisation maintenant ? (o/N) " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Oo]$ ]]; then
            systemctl start "${SERVICE_NAME}.timer"
            echo_success "Timer démarré"
            
            echo_info "Lancement d'une synchronisation manuelle..."
            systemctl start "${SERVICE_NAME}.service"
            echo_success "Synchronisation lancée"
        fi
    else
        echo_warning "Services non activés. Pour les activer manuellement :"
        echo "  sudo systemctl enable ${SERVICE_NAME}.timer"
        echo "  sudo systemctl enable ${SERVICE_NAME}-shutdown.service"
        echo "  sudo systemctl start ${SERVICE_NAME}.timer"
    fi
}

# Afficher les informations finales
show_summary() {
    local real_user=$(get_real_user)
    
    echo ""
    echo_success "═══════════════════════════════════════════════════"
    echo_success "   Installation terminée avec succès !"
    echo_success "═══════════════════════════════════════════════════"
    echo ""
    echo_info "Fichiers installés :"
    echo "  • Script principal : $INSTALL_DIR/pistomp-sync.sh"
    echo "  • Lien symbolique  : $BIN_DIR/pistomp-sync"
    echo "  • Configuration    : $CONFIG_DIR/pistomp-sync.conf"
    echo "  • Logs            : $LOG_DIR/pistomp-sync.log"
    echo ""
    echo_info "Services systemd :"
    echo "  • ${SERVICE_NAME}.service         : Synchronisation unique"
    echo "  • ${SERVICE_NAME}.timer           : Synchronisation périodique (15 min)"
    echo "  • ${SERVICE_NAME}-shutdown.service : Sync avant arrêt"
    echo ""
    echo_info "Commandes utiles :"
    echo "  # Éditer la configuration"
    echo "  sudo nano $CONFIG_DIR/pistomp-sync.conf"
    echo ""
    echo "  # Lister les synchronisations configurées"
    echo "  pistomp-sync --list"
    echo ""
    echo "  # Test en mode dry-run"
    echo "  pistomp-sync --dry-run"
    echo ""
    echo "  # Synchronisation manuelle"
    echo "  sudo systemctl start ${SERVICE_NAME}.service"
    echo ""
    echo "  # Voir le statut"
    echo "  systemctl status ${SERVICE_NAME}.timer"
    echo "  systemctl status ${SERVICE_NAME}.service"
    echo ""
    echo "  # Voir les logs"
    echo "  tail -f $LOG_DIR/pistomp-sync.log"
    echo "  journalctl -u ${SERVICE_NAME}.service -f"
    echo ""
    echo "  # Activer/désactiver le timer"
    echo "  sudo systemctl enable ${SERVICE_NAME}.timer"
    echo "  sudo systemctl disable ${SERVICE_NAME}.timer"
    echo ""
    echo_warning "⚠️  N'oubliez pas de :"
    echo "  1. Configurer rclone si ce n'est pas déjà fait (rclone config)"
    echo "  2. Éditer $CONFIG_DIR/pistomp-sync.conf"
    echo "  3. Tester avec : pistomp-sync --dry-run"
    echo ""
}

# Programme principal
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║   Installation de PiStomp Sync                    ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    install_dependencies
    create_directories
    install_files
    create_default_config
    create_systemd_service
    setup_log_permissions
    enable_services
    show_summary
}

# Exécuter
main
