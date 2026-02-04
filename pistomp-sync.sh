#!/bin/sh
set -eu

###############################################################################
# CONFIG
###############################################################################

SCRIPT_NAME="pistomp-sync"
BASE_DIR="/usr/local/lib/pistomp-sync"
DATA_DIR="/home/pistomp/data"
SYNC_DIR="$DATA_DIR/sync"
STATE_DIR="$SYNC_DIR/state"
LOG_DIR="$SYNC_DIR/log"
CONFIG_FILE="$DATA_DIR/config/sync.yml"

RCLONE_BIN="/usr/bin/rclone"

###############################################################################
# ARGS
###############################################################################

DRY_RUN=0
RESYNC=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --resync)  RESYNC=1 ;;
  esac
done

###############################################################################
# LOGGING
###############################################################################

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

log "### Starting $SCRIPT_NAME at $(date) ###"

[ "$DRY_RUN" -eq 1 ] && log "### DRY-RUN mode enabled ###"

###############################################################################
# CHECKS
###############################################################################

[ -f "$CONFIG_FILE" ] || {
  log "ERROR: missing $CONFIG_FILE"
  exit 1
}

###############################################################################
# PARSE YAML (simple, controlled format)
###############################################################################

REMOTE_NAME=$(awk '/remote:/,/paths:/' "$CONFIG_FILE" | awk '/name:/ {print $2}')
REMOTE_BASE=$(awk '/remote:/,/paths:/' "$CONFIG_FILE" | awk '/base_path:/ {print $2}')

REMOTE="${REMOTE_NAME}:${REMOTE_BASE}"

###############################################################################
# NETWORK / REMOTE CHECK
###############################################################################

if ! $RCLONE_BIN lsf "${REMOTE_NAME}:" >/dev/null 2>&1; then
  log "Remote ${REMOTE_NAME} unreachable, skipping sync"
  exit 0
fi

###############################################################################
# ENSURE REMOTE BASE EXISTS
###############################################################################

$RCLONE_BIN mkdir "$REMOTE" >/dev/null 2>&1 || true

###############################################################################
# READ PATHS
###############################################################################

PATHS=$(awk '
  $1 ~ /^[a-zA-Z0-9_-]+:/ { section=substr($1,1,length($1)-1) }
  /enabled:/ { enabled=$2 }
  /local:/ { local=$2 }
  /remote:/ { remote=$2 }
  /mode:/ {
    mode=$2
    if (enabled=="true") {
      print section "|" local "|" remote "|" mode
    }
  }
' "$CONFIG_FILE")

###############################################################################
# SYNC LOOP
###############################################################################

for entry in $PATHS; do
  IFS="|" set -- $entry
  NAME="$1"
  LOCAL="$2"
  REMOTE_PATH="$REMOTE/$3"
  MODE="$4"

  log "--------------------------------------------------"
  log "[$NAME]"
  log "  local : $LOCAL"
  log "  remote: $REMOTE_PATH"
  log "  mode  : $MODE"

  [ -e "$LOCAL" ] || {
    log "[$NAME] local path missing, skipping"
    continue
  }

  # Ensure remote dir exists (even for files)
  $RCLONE_BIN mkdir "$REMOTE_PATH" >/dev/null 2>&1 || true

  # Directory
  if [ -d "$LOCAL" ]; then
    KEEP_FILE="$LOCAL/.keep"
    [ -f "$KEEP_FILE" ] || touch "$KEEP_FILE"

    CMD="$RCLONE_BIN bisync \"$LOCAL\" \"$REMOTE_PATH\" \
      --workdir \"$STATE_DIR/$NAME\" \
      --resilient --compare size,modtime --create-empty-src-dirs"

    [ "$RESYNC" -eq 1 ] && CMD="$CMD --resync"
    [ "$DRY_RUN" -eq 1 ] && CMD="$CMD --dry-run"

    sh -c "$CMD" || log "[$NAME] bisync failed (continuing)"

  # File
  else
    log "[$NAME] single file detected, using rclone copy"

    CMD="$RCLONE_BIN copy \"$LOCAL\" \"$REMOTE_PATH\" --ignore-existing"
    [ "$DRY_RUN" -eq 1 ] && CMD="$CMD --dry-run"

    sh -c "$CMD" || log "[$NAME] file copy failed"
  fi
done

log "### $SCRIPT_NAME finished at $(date) ###"
