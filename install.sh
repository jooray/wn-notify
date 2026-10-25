#!/bin/sh
# Symlink wn-notify and its aliases into a bin directory (default: ~/.local/bin).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest=${1:-"$HOME/.local/bin"}
mkdir -p "$dest"
ln -sf "$here/wn-notify" "$dest/wn-notify"
for alias in wn-msg wn-stdin wn-file; do
  ln -sf wn-notify "$dest/$alias"
done
echo "Linked wn-notify, wn-msg, wn-stdin and wn-file into $dest"
