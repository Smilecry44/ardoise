#!/bin/bash
# Ardoise — local install from this folder (for development).
# Users installing from the marketplace or `omarchy plugin add` do not need this script.
set -euo pipefail
cd "$(dirname "$0")"

id="io.github.smilecry44.ardoise"
dest="$HOME/.config/omarchy/plugins/$id"
mkdir -p "$dest"
rm -f "$dest"/*.qml
install -m 644 manifest.json *.qml "$dest/"
install -m 755 ardoise "$dest/ardoise"
for f in README.md LICENSE preview.png; do [ -f "$f" ] && install -m 644 "$f" "$dest/"; done

# optional terminal command
mkdir -p "$HOME/.local/bin"
ln -sfn "$dest/ardoise" "$HOME/.local/bin/ardoise"

echo "plugin  -> $dest"
echo "command -> $HOME/.local/bin/ardoise"
echo "then: omarchy restart shell"
