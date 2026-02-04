#!/bin/sh

# extract the block for a given section
yaml_get_block() {
  section="$1"
  file="$2"
  sed -n "/^$section:/,/^[^ ]/p" "$file"
}
