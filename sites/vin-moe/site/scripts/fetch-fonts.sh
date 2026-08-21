#!/bin/sh
set -eu

dir="${1:?usage: fetch-fonts.sh <target-dir>}"
mkdir -p "$dir"
cd "$dir"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
curl -fsSL -A "$UA" \
  "https://fonts.googleapis.com/css2?family=Fira+Code:wght@300..700&display=swap" \
  -o fira-code.css

grep -oE 'https://fonts\.gstatic\.com/[a-zA-Z0-9._/-]+\.woff2' fira-code.css | sort -u | while IFS= read -r url; do
  fname="$(basename "$url")"
  curl -fsSL "$url" -o "$fname"
  sed -i "s#$url#./$fname#g" fira-code.css
done
