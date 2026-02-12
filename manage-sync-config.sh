#!/bin/bash
# manage-sync-config.sh - Gérer les sections de configuration

CONFIG_FILE="$HOME/.config/pistomp-sync.conf"

add_section() {
    echo ""
    echo "═══ Ajout d'une nouvelle synchronisation ═══"
    echo ""
    
    read -p "Nom de la section (ex: pedalboards): " section
    read -p "Chemin local: " local_path
    read -p "Chemin remote: " remote_path
    read -p "Description: " description
    read -p "Activé? (true/false) [true]: " enabled
    enabled=${enabled:-true}
    
    cat >> "$CONFIG_FILE" << EOF

# Section $section
[$section]
local = $local_path
remote = $remote_path
description = $description
enabled = $enabled
EOF
    
    echo ""
    echo "✅ Section ajoutée avec succès !"
}

disable_section() {
    echo ""
    read -p "Nom de la section à désactiver: " section
    sed -i "/^\[$section\]/,/^$/s/^enabled = true/enabled = false/" "$CONFIG_FILE"
    echo "✅ Section '$section' désactivée"
}

enable_section() {
    echo ""
    read -p "Nom de la section à activer: " section
    sed -i "/^\[$section\]/,/^$/s/^enabled = false/enabled = true/" "$CONFIG_FILE"
    echo "✅ Section '$section' activée"
}

case "$1" in
    add)
        add_section
        ;;
    disable)
        disable_section
        ;;
    enable)
        enable_section
        ;;
    *)
        echo "Usage: $0 {add|disable|enable}"
        exit 1
        ;;
esac
