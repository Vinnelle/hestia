#!/bin/sh
set -eu

dir="${1:?usage: fetch-fonts.sh <target-dir>}"
mkdir -p "$dir"
cd "$dir"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
curl -fsSL -A "$UA" \
  "https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,400;0,500;0,700;1,400&display=swap" \
  -o jetbrains-mono.css

grep -oE 'https://fonts\.gstatic\.com/[a-zA-Z0-9._/-]+\.woff2' jetbrains-mono.css | sort -u | while IFS= read -r url; do
  fname="$(basename "$url")"
  curl -fsSL "$url" -o "$fname"
  sed -i "s#$url#./$fname#g" jetbrains-mono.css
done
