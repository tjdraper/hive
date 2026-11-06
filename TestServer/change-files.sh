#!/bin/bash
# Changes some sample files between backup runs: one edited, one added, one removed. Everything else
# stays the same, so a second snapshot can link it.
set -euo pipefail

site=/srv/sites/example
stamp=$(date +%Y%m%d-%H%M%S)

count=$(( $(cat "$site/uploads/counter.txt") + 1 ))
echo "$count" > "$site/uploads/counter.txt"

head -c 30000 /dev/urandom > "$site/uploads/2026/11/added-$stamp.bin"

oldest=$(find "$site/uploads/2026/11" -name 'added-*.bin' | sort | head -n 1)
if [[ -n "$oldest" && $(find "$site/uploads/2026/11" -name 'added-*.bin' | wc -l) -gt 2 ]]; then
    rm "$oldest"
    echo "Removed $(basename "$oldest")"
fi

chown -R www-data:www-data "$site/uploads"
echo "Changed counter.txt to $count and added added-$stamp.bin"
