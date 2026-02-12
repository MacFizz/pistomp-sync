#!/bin/bash
# pistomp-sync.sh - Synchronisation multi-répertoires et fichiers avec rclone

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/etc/pistomp-sync/pistomp-sync.conf}"
LOCK_FILE="nxt:Apps/pistomp_sync/.rclone-sync.lock"
MACHINE_ID="$(hostname)-$$"
MAX_LOCK_AGE=600  # 10 minutes
LOG_FILE="/var/log/pistomp-sync.log"

# Mode dry-run
DRY_RUN=false

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonction d'aide
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help              Afficher cette aide
    -c, --config FILE       Utiliser un fichier de configuration spécifique
                           (défaut: $HOME/.config/pistomp-sync.conf)
    -d, --dry-run          Mode simulation (aucun fichier n'est modifié)
    -v, --verbose          Mode verbeux
    -l, --list             Lister les synchronisations configurées
    -s, --sync NAME        Synchroniser uniquement une section spécifique

Exemples:
    $0                          # Synchronisation normale
    $0 --dry-run                # Simulation
    $0 --sync pedalboards       # Synchroniser uniquement les pedalboards
    $0 -c /path/to/config.conf  # Utiliser un autre fichier de config

Variables d'environnement:
    CONFIG_FILE             Chemin vers le fichier de configuration
    DRY_RUN=1              Activer le mode dry-run

EOF
    exit 0
}

# Fonction de log
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

log_dry_run() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] 🔍 [DRY-RUN] $1${NC}" | tee -a "$LOG_FILE"
}

# Parser le fichier de configuration INI
parse_config() {
    local config_file="$1"
    local section=""
    
    declare -gA CONFIG_SECTIONS
    declare -gA CONFIG_DATA
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Supprimer les espaces en début et fin
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Ignorer les lignes vides et les commentaires
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue
        
        # Détecter une section [nom]
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            CONFIG_SECTIONS["$section"]=1
            continue
        fi
        
        # Parser les paires clé=valeur
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]] && [[ -n "$section" ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Nettoyer les espaces
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            
            CONFIG_DATA["${section}.${key}"]="$value"
        fi
    done < "$config_file"
}

# Obtenir une valeur de configuration
get_config() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    
    local value="${CONFIG_DATA[${section}.${key}]}"
    echo "${value:-$default}"
}

# Lister les synchronisations configurées
list_syncs() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         Synchronisations configurées                          ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    for section in "${!CONFIG_SECTIONS[@]}"; do
        local enabled=$(get_config "$section" "enabled" "true")
        local description=$(get_config "$section" "description" "$section")
        local local_path=$(get_config "$section" "local")
        local remote_path=$(get_config "$section" "remote")
        local sync_type="répertoire"
        
        # Détecter si c'est un fichier
        if [[ "$local_path" != */ ]]; then
            sync_type="fichier"
        fi
        
        local status_icon="✅"
        local status_color="$GREEN"
        [[ "$enabled" != "true" ]] && status_icon="🚫" && status_color="$YELLOW"
        
        echo -e "${status_color}[$section] ($sync_type)${NC}"
        echo "  Description: $description"
        echo "  Local:       $local_path"
        echo "  Remote:      $remote_path"
        echo "  Activé:      $enabled"
        echo ""
    done
}

# Fonction pour obtenir l'âge du lock
get_lock_age() {
    rclone cat "$LOCK_FILE" 2>/dev/null | cut -d'|' -f2
}

# Fonction pour vérifier si le lock est expiré
is_lock_expired() {
    local lock_time=$(get_lock_age)
    if [ -z "$lock_time" ]; then
        return 0  # Pas de lock
    fi
    local current_time=$(date +%s)
    local age=$((current_time - lock_time))
    [ $age -gt $MAX_LOCK_AGE ]
}

# Tentative d'acquisition du lock
acquire_lock() {
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Mode dry-run: acquisition du lock ignorée"
        return 0
    fi
    
    if rclone lsf "$LOCK_FILE" >/dev/null 2>&1; then
        if ! is_lock_expired; then
            log_warning "Lock déjà présent et valide, abandon"
            return 1
        else
            log_info "Lock expiré, suppression et réacquisition"
            rclone delete "$LOCK_FILE" 2>/dev/null
        fi
    fi
    
    # Créer le fichier de lock
    echo "$MACHINE_ID|$(date +%s)" | rclone rcat "$LOCK_FILE"
    sleep 2
    
    # Vérifier qu'on a bien le lock
    local current_lock=$(rclone cat "$LOCK_FILE" 2>/dev/null)
    if [[ "$current_lock" == "$MACHINE_ID|"* ]]; then
        return 0
    else
        log_error "Conflit de lock détecté, abandon"
        return 1
    fi
}

# Libération du lock
release_lock() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    rclone delete "$LOCK_FILE" 2>/dev/null
}

# Synchroniser un fichier bidirectionnel
sync_file() {
    local section="$1"
    local local_file="$2"
    local remote_file="$3"
    local description="$4"
    
    log_info "Type: Fichier unique"
    
    # Vérifier l'existence du fichier local
    local local_exists=false
    local remote_exists=false
    
    if [ -f "$local_file" ]; then
        local_exists=true
    fi
    
    if rclone lsf "$remote_file" >/dev/null 2>&1; then
        remote_exists=true
    fi
    
    # Construire les options rclone de base
    local rclone_opts=("--verbose")
    
    if [ "$DRY_RUN" = true ]; then
        rclone_opts+=("--dry-run")
    fi
    
    # Cas 1: Les deux fichiers existent - comparer et synchroniser
    if [ "$local_exists" = true ] && [ "$remote_exists" = true ]; then
        log_info "Fichiers présents des deux côtés, comparaison..."
        
        # Obtenir les timestamps
        local local_mtime=$(stat -c %Y "$local_file" 2>/dev/null || echo "0")
        local remote_info=$(rclone lsl "$remote_file" 2>/dev/null | head -1)
        
        # Extraire la date du fichier distant (format rclone lsl)
        local remote_mtime=$(echo "$remote_info" | awk '{print $2, $3}')
        local remote_timestamp=$(date -d "$remote_mtime" +%s 2>/dev/null || echo "0")
        
        if [ "$local_mtime" -gt "$remote_timestamp" ]; then
            log_info "Fichier local plus récent, envoi vers distant..."
            if [ "$DRY_RUN" = true ]; then
                log_dry_run "rclone copyto $local_file $remote_file ${rclone_opts[*]}"
                return 0
            else
                rclone copyto "$local_file" "$remote_file" "${rclone_opts[@]}" 2>&1 | tee -a "$LOG_FILE"
                return $?
            fi
        elif [ "$remote_timestamp" -gt "$local_mtime" ]; then
            log_info "Fichier distant plus récent, téléchargement..."
            if [ "$DRY_RUN" = true ]; then
                log_dry_run "rclone copyto $remote_file $local_file ${rclone_opts[*]}"
                return 0
            else
                rclone copyto "$remote_file" "$local_file" "${rclone_opts[@]}" 2>&1 | tee -a "$LOG_FILE"
                return $?
            fi
        else
            log_info "Fichiers identiques (même date de modification)"
            return 0
        fi
        
    # Cas 2: Seulement le fichier local existe
    elif [ "$local_exists" = true ]; then
        log_info "Fichier local existe, envoi vers distant..."
        if [ "$DRY_RUN" = true ]; then
            log_dry_run "rclone copyto $local_file $remote_file ${rclone_opts[*]}"
            return 0
        else
            rclone copyto "$local_file" "$remote_file" "${rclone_opts[@]}" 2>&1 | tee -a "$LOG_FILE"
            return $?
        fi
        
    # Cas 3: Seulement le fichier distant existe
    elif [ "$remote_exists" = true ]; then
        log_info "Fichier distant existe, téléchargement..."
        
        # Créer le répertoire parent si nécessaire
        local parent_dir=$(dirname "$local_file")
        if [ ! -d "$parent_dir" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_dry_run "mkdir -p $parent_dir"
            else
                mkdir -p "$parent_dir"
            fi
        fi
        
        if [ "$DRY_RUN" = true ]; then
            log_dry_run "rclone copyto $remote_file $local_file ${rclone_opts[*]}"
            return 0
        else
            rclone copyto "$remote_file" "$local_file" "${rclone_opts[@]}" 2>&1 | tee -a "$LOG_FILE"
            return $?
        fi
        
    # Cas 4: Aucun fichier n'existe
    else
        log_warning "Aucun fichier trouvé ni local ni distant"
        return 1
    fi
}

# Créer les fichiers RCLONE_TEST si nécessaire
ensure_check_access_files() {
    local local_path="$1"
    local remote_path="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Vérification fichiers RCLONE_TEST (non créés en dry-run)"
        return 0
    fi
    
    if [ ! -f "${local_path}RCLONE_TEST" ]; then
        log_info "Création du fichier RCLONE_TEST local"
        touch "${local_path}RCLONE_TEST"
    fi
    
    if ! rclone lsf "${remote_path}RCLONE_TEST" >/dev/null 2>&1; then
        log_info "Création du fichier RCLONE_TEST distant"
        echo "" | rclone rcat "${remote_path}RCLONE_TEST"
    fi
}

# Synchroniser un répertoire avec bisync
sync_directory_bisync() {
    local section="$1"
    local local_path="$2"
    local remote_path="$3"
    local description="$4"
    
    log_info "Type: Répertoire (bisync)"
    
    # Vérifier que le répertoire local existe
    if [ ! -d "$local_path" ]; then
        log_warning "Le répertoire local n'existe pas: ${local_path}"
        if [ "$DRY_RUN" = true ]; then
            log_dry_run "mkdir -p $local_path"
        else
            log_info "Création du répertoire..."
            mkdir -p "$local_path"
        fi
    fi
    
    # Créer les fichiers de vérification d'accès
    ensure_check_access_files "$local_path" "$remote_path"
    
    # Vérifier si première sync
    local bisync_dir="$HOME/.cache/rclone/bisync"
    local listing_exists=$(find "$bisync_dir" -type f -name "*.lst" 2>/dev/null | grep -v ".*\.lst-.*" | head -n 1)
    
    # Construire les options rclone
    local rclone_opts=(
        "--verbose"
        "--links"
        "--create-empty-src-dirs"
    )
    
    # Ajouter l'option dry-run si nécessaire
    if [ "$DRY_RUN" = true ]; then
        rclone_opts+=("--dry-run")
        log_dry_run "Mode simulation activé"
    fi
    
    if [ -z "$listing_exists" ]; then
        log_info "Première synchronisation détectée"
        if [ "$DRY_RUN" = true ]; then
            log_dry_run "rclone bisync --resync $local_path $remote_path ${rclone_opts[*]}"
        fi
        
        rclone bisync "$local_path" "$remote_path" \
            --resync \
            "${rclone_opts[@]}" 2>&1 | tee -a "$LOG_FILE"
        return $?
    else
        log_info "Synchronisation normale"
        
        # Options supplémentaires pour sync normale
        local normal_opts=(
            "${rclone_opts[@]}"
            "--check-access"
            "--max-delete" "10"
            "--conflict-resolve" "newer"
            "--conflict-loser" "num"
        )
        
        if [ "$DRY_RUN" = true ]; then
            log_dry_run "rclone bisync $local_path $remote_path ${normal_opts[*]}"
        fi
        
        # Tentative de sync avec gestion d'erreur
        if rclone bisync "$local_path" "$remote_path" \
            "${normal_opts[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        else
            # Vérifier si c'est une erreur nécessitant un resync
            if tail -20 "$LOG_FILE" | grep -q "Must run --resync"; then
                log_warning "Resync nécessaire suite à une erreur"
                rclone bisync "$local_path" "$remote_path" \
                    --resync \
                    "${rclone_opts[@]}" 2>&1 | tee -a "$LOG_FILE"
                return $?
            fi
            return 1
        fi
    fi
}

# Synchroniser (fichier ou répertoire)
sync_item() {
    local section="$1"
    local local_path=$(get_config "$section" "local")
    local remote_path=$(get_config "$section" "remote")
    local description=$(get_config "$section" "description" "$section")
    local enabled=$(get_config "$section" "enabled" "true")
    
    # Vérifier si activé
    if [[ "$enabled" != "true" ]]; then
        log_warning "[$section] désactivé, ignoré"
        return 2
    fi
    
    # Valider les chemins
    if [ -z "$local_path" ] || [ -z "$remote_path" ]; then
        log_error "[$section] Configuration invalide: chemins manquants"
        return 1
    fi
    
    log_info "════════════════════════════════════════════════════"
    log_info "Début synchronisation: ${description} [$section]"
    log_info "  Local:  ${local_path}"
    log_info "  Remote: ${remote_path}"
    
    # Déterminer si c'est un fichier ou un répertoire
    local is_directory=false
    if [[ "$local_path" == */ ]]; then
        is_directory=true
    fi
    
    local sync_result
    if [ "$is_directory" = true ]; then
        sync_directory_bisync "$section" "$local_path" "$remote_path" "$description"
        sync_result=$?
    else
        sync_file "$section" "$local_path" "$remote_path" "$description"
        sync_result=$?
    fi
    
    if [ $sync_result -eq 0 ]; then
        log_success "Synchronisation réussie: ${description} [$section]"
        return 0
    else
        log_error "Échec de la synchronisation: ${description} [$section]"
        return 1
    fi
}

# Fonction de nettoyage
cleanup() {
    release_lock
    exit
}

trap cleanup EXIT INT TERM

# Parser les arguments
SPECIFIC_SYNC=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        -l|--list)
            parse_config "$CONFIG_FILE"
            list_syncs
            exit 0
            ;;
        -s|--sync)
            SPECIFIC_SYNC="$2"
            shift 2
            ;;
        *)
            echo "Option inconnue: $1"
            show_help
            ;;
    esac
done

# Vérifier que le fichier de configuration existe
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Fichier de configuration non trouvé: $CONFIG_FILE"
    echo ""
    echo "Créez un fichier de configuration avec le format suivant:"
    cat << 'EOF'

[section_name]
local = /chemin/local/repertoire/  # Pour un répertoire (doit finir par /)
remote = remote:chemin/distant/
description = Description
enabled = true

[fichier_unique]
local = /chemin/vers/fichier.json  # Pour un fichier (pas de / final)
remote = remote:chemin/fichier.json
description = Mon fichier
enabled = true

EOF
    exit 1
fi

# Parser la configuration
parse_config "$CONFIG_FILE"

# Programme principal
log_info "=========================================="
if [ "$DRY_RUN" = true ]; then
    log_dry_run "MODE SIMULATION - Aucune modification ne sera effectuée"
fi
log_info "Démarrage de pistomp-sync"
log_info "Configuration: $CONFIG_FILE"
log_info "=========================================="

if acquire_lock; then
    if [ "$DRY_RUN" = false ]; then
        log_success "Lock acquis avec succès"
    fi
    
    # Compteurs
    total=0
    success=0
    failed=0
    skipped=0
    
    # Traiter les sections
    for section in "${!CONFIG_SECTIONS[@]}"; do
        # Si une section spécifique est demandée, ne traiter que celle-là
        if [[ -n "$SPECIFIC_SYNC" ]] && [[ "$section" != "$SPECIFIC_SYNC" ]]; then
            continue
        fi
        
        echo ""
        sync_item "$section"
        sync_result=$?
        
        case $sync_result in
            0)
                ((total++))
                ((success++))
                ;;
            2)
                ((skipped++))
                ;;
            *)
                ((total++))
                ((failed++))
                ;;
        esac
    done
    
    echo ""
    log_info "=========================================="
    log_info "Résumé de la synchronisation"
    log_info "Total traité: $total | Réussies: $success | Échouées: $failed | Ignorées: $skipped"
    log_info "=========================================="
    
    if [ $failed -eq 0 ] && [ $total -gt 0 ]; then
        log_success "Toutes les synchronisations ont réussi !"
        exit 0
    elif [ $total -eq 0 ]; then
        if [ $skipped -gt 0 ]; then
            log_warning "Aucune synchronisation active (toutes désactivées)"
        else
            log_warning "Aucune synchronisation configurée"
        fi
        exit 0
    else
        log_error "$failed synchronisation(s) ont échoué"
        exit 1
    fi
else
    log_error "Impossible d'acquérir le lock, une autre synchronisation est en cours"
    exit 1
fi
