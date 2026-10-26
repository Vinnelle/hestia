#!/bin/sh
set -eu

dir=${MODEL_DIR:-/models}
target="$dir/$MODEL_FILE"

if [ -f "$target" ] && [ "$(cat "$target.sha256" 2>/dev/null)" = "$MODEL_SHA256" ]; then
  exit 0
fi

for f in "$dir"/*.gguf "$dir"/*.gguf.*; do
  case "$f" in
    "$target.part") ;;
    *) rm -f "$f" ;;
  esac
done

echo "downloading $MODEL_FILE"
wget -q -c -O "$target.part" "$MODEL_URL"
if ! echo "$MODEL_SHA256  $target.part" | sha256sum -c -s; then
  rm -f "$target.part"
  echo "$MODEL_FILE does not match its pinned sha256" >&2
  exit 1
fi
mv "$target.part" "$target"
printf '%s\n' "$MODEL_SHA256" > "$target.sha256"
echo "verified $MODEL_FILE"
