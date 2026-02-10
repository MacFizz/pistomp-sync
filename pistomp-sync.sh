#!/usr/bin/env bash
set -euo pipefail

# --------------------------
# Configuration
# --------------------------
CONFIG="/home/pistomp/data/config/sync.yml"
YAML_LIB="/usr/local/lib/pistomp-sync/lib/yaml.sh"

[[ -f "$CONFIG" ]] || { echo "Config missing: $CONFIG"; exit 1; }
source "$YAML_LIB"
eval "$(parse_yaml "$CONFIG")"

# --- Assigner les variables runtime ---
STATE_DIR="${yaml_runtime_state_dir:-/home/pistomp/data/sync/state}"
LOCKFILE="${yaml_runtime_lockfile:-/home/pistomp/data/sync/pistomp-sync.lock}"
LOGFILE="${yaml_runtime_logfile:-/home/pistomp/data/sync/logs/pistomp-sync.log}"
mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "### $1" | tee -a "$LOGFILE"; }

# --------------------------
# Lock pour éviter double execution
# --------------------------
exec 9>"$LOCKFILE"
flock -n 9 || { log "Another instance running, exiting"; exit 0; }

log "Starting pistomp-sync at $(date)"
$DRY_RUN && log "### DRY-RUN enabled"

# --------------------------
# Rclone remote
# --------------------------
RCLONE_REMOTE="${yaml_rclone_remote:-}"
RCLONE_BASE_PATH="${yaml_rclone_base_path:-}"

[[ -n "$RCLONE_REMOTE" && -n "$RCLONE_BASE_PATH" ]] || {
    log "Rclone remote/base_path not defined in YAML"
    exit 1
}

RCLONE_BASE="${RCLONE_REMOTE}:${RCLONE_BASE_PATH}"

# test remote
if ! rclone lsf "$RCLONE_BASE" >/dev/null 2>&1; then
    log "Remote $RCLONE_BASE unreachable, skipping"
    exit 0
fi

RCLONE_OPTS=(--dry-run) 
$DRY_RUN || RCLONE_OPTS=()

# --------------------------
# Déterminer les chemins à synchroniser dynamiquement
# --------------------------
PATH_NAMES=()
for var in $(compgen -v | grep '^yaml_paths_'); do
    if [[ "$var" =~ _enabled$ ]]; then
        PATH_NAMES+=("${var#yaml_paths_}")
        PATH_NAMES[-1]=${PATH_NAMES[-1]%_enabled}
    fi
done

if [[ ${#PATH_NAMES[@]} -eq 0 ]]; then
    log "No paths defined in YAML to sync"
    exit 0
fi

# --------------------------
# Création de logs spécifiques pour chaque répertoire/fichier
# --------------------------
declare -A PATH_LOGS

for pathname in "${PATH_NAMES[@]}"; do
    # Nom sûr pour fichier log
    safe_name=$(echo "$pathname" | tr '/ ' '__')
    PATH_LOGS["$pathname"]="/home/pistomp/data/sync/logs/${safe_name}.log"
    mkdir -p "$(dirname "${PATH_LOGS[$pathname]}")"
    touch "${PATH_LOGS[$pathname]}"
done

# Fonction de log spécifique à un path
log_path() {
    local msg="$1"
    local p="$2"
    echo "### $msg" | tee -a "${PATH_LOGS[$p]}"
}

# --------------------------
# Boucle sur les chemins
# --------------------------
for pathname in "${PATH_NAMES[@]}"; do
    enabled_var="yaml_paths_${pathname}_enabled"
    local_var="yaml_paths_${pathname}_local"
    remote_var="yaml_paths_${pathname}_remote"
    mode_var="yaml_paths_${pathname}_mode"

    [[ "${!enabled_var:-false}" != "true" ]] && continue

    SRC="${!local_var:-}"
    DST="$RCLONE_BASE/${!remote_var:-}"
    MODE="${!mode_var:-copy}"

    [[ -z "$SRC" || -z "$DST" ]] && { log "Skipping $pathname, source or remote not defined"; continue; }

    log "--------------------------------------------------"
    log "[$pathname] local: $SRC, remote: $DST, mode: $MODE"

    {
        echo
        echo "=================================================="
        echo "Run at $(date)"
        echo "=================================================="
        echo "Local : $SRC"
        echo "Remote: $DST"
        echo "Mode  : $MODE"
    } >> "${PATH_LOGS[$pathname]}"

    log_path "Starting sync for $pathname" "$pathname"

    if [[ "$MODE" == "bisync" ]]; then
        WORKDIR="$STATE_DIR/$pathname"
        mkdir -p "$WORKDIR"

        [[ ! -d "$SRC" ]] && {
            log "Local source $SRC missing, skipping"
            log_path "Local source missing, skipping" "$pathname"
            continue
        }

        log "Running bisync $SRC <-> $DST"
        log_path "Running bisync $SRC <-> $DST" "$pathname"

	set +e
        rclone bisync -L "$SRC" "$DST" \
            --workdir "$WORKDIR" \
            --ignore-errors \
            --resilient \
            --check-access \
            "${RCLONE_OPTS[@]}" \
            >> "${PATH_LOGS[$pathname]}" 2>&1
        rc=$?
	set -e

        if [[ $rc -ne 0 ]]; then
            log_path "rclone bisync exited with code $rc (see log)" "$pathname"
            log "[$pathname] rclone bisync exit code=$rc"
        else
            log_path "bisync completed successfully" "$pathname"
        fi

    else
        [[ ! -e "$SRC" ]] && {
            log "Local source $SRC missing, skipping"
            log_path "Local source missing, skipping" "$pathname"
            continue
        }

        log "Running copy $SRC -> $DST"
        log_path "Running copy $SRC -> $DST" "$pathname"

	set +e
        rclone copy -L "$SRC" "$DST" \
            "${RCLONE_OPTS[@]}" \
            --ignore-errors \
            >> "${PATH_LOGS[$pathname]}" 2>&1
        rc=$?
	set -e

        if [[ $rc -ne 0 ]]; then
            log_path "rclone copy exited with code $rc (see log)" "$pathname"
            log "[$pathname] rclone copy exit code=$rc"
        else
            log_path "copy completed successfully" "$pathname"
        fi
    fi
done

log "### pistomp-sync finished at $(date)"
exit 0
