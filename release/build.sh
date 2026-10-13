#!/bin/sh
# Builds the add-on's zip: the files the .toc lists (the empty inbox included) and the .toc with
# the version stamped in, all in one BureaucracyForever folder. The version is never committed:
# the .toc in git says 0.0.0-dev. Run from the repo root; prints the zip's path.
# Usage: sh release/build.sh <version> <out-dir>
set -eu
version=$1
out=$2
name=BureaucracyForever
case $version in '' | *[!A-Za-z0-9.-]*) echo "not a version: $version" >&2; exit 1 ;; esac

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$name" "$out"

# Lines that aren't blank or comments are files, with the game's backslashes.
tr -d '\r' < "$name.toc" | grep -v '^#' | sed 's/[[:space:]]*$//' | grep . | tr '\\' '/' |
  while read -r file; do
    mkdir -p "$stage/$name/$(dirname "$file")"
    cp "$file" "$stage/$name/$file"
  done
sed "s/^## Version:.*/## Version: $version/" "$name.toc" > "$stage/$name/$name.toc"
grep -q "^## Version: $version" "$stage/$name/$name.toc"

zip="$out/$name-$version.zip"
rm -f "$zip"
(cd "$stage" && zip -qrX - "$name") > "$zip"
echo "$zip"
