#!/usr/bin/env bash
# ------------------------------------------------------------
# yaml.sh — minimal YAML parser for simple key/value configs
# Compatible with:
#   - key: value
#   - nested keys via indentation (2 spaces)
#   - booleans, strings
#
# NOT supported (by design):
#   - lists
#   - inline objects
#   - anchors / aliases
#
# Usage:
#   eval "$(parse_yaml sync.yml)"
#
# Example:
#   yaml_rclone_remote="nxt"
#   yaml_sync_pedalboards_mode="bisync"
# ------------------------------------------------------------

parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-yaml_}"

    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs
    fs=$(printf '\034')

    sed -ne "
        s|^\($s\):|\1|;                             # skip empty keys
        s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p;
        s|^\($s\)\($w\)$s:$s'\(.*\)'$s\$|\1$fs\2$fs\3|p;
        s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p;
    " "$yaml_file" |
    awk -F"$fs" '
    {
        indent = length($1) / 2
        key[indent] = $2
        for (i in key) {
            if (i > indent) delete key[i]
        }
        if (length($3) > 0) {
            fullkey = key[0]
            for (i = 1; i < indent; i++) {
                fullkey = fullkey "_" key[i]
            }
            printf("%s%s_%s=\"%s\"\n", "'"$prefix"'", fullkey, $2, $3)
        }
    }'
}
