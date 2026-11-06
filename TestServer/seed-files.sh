#!/bin/bash
# Sample files to back up: nested folders, names differing only in case, spaces, a symbolic link,
# an empty file, and owners and groups other than root, under /srv/sites/example.
set -euo pipefail

site=/srv/sites/example
mkdir -p "$site/uploads/2026/11" "$site/images/galleries/summer" "$site/config"

head -c 200000 /dev/urandom > "$site/uploads/2026/11/photo.jpg"
head -c 50000 /dev/urandom > "$site/images/galleries/summer/Foo.jpg"
head -c 50000 /dev/urandom > "$site/images/galleries/summer/foo.jpg"
echo "a file with spaces in its name" > "$site/uploads/2026/11/read me.txt"
: > "$site/uploads/empty.txt"
echo "APP_KEY=not-a-real-secret" > "$site/config/.env"
ln -s ../uploads/2026/11/photo.jpg "$site/images/latest.jpg"
echo 0 > "$site/uploads/counter.txt"

chown -R www-data:www-data "$site/uploads"
chown 33:999 "$site/images/galleries/summer/foo.jpg"
chmod 640 "$site/config/.env"

echo "Seeded $(find "$site" -type f | wc -l) files under $site"
