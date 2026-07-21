#!/bin/sh
set -e

cleancss -O2 -o assets/css/style.css assets/css/style.css

STYLE_HASH=$(md5sum assets/css/style.css | cut -c1-8)

find . -name "*.html" -exec sed -i \
  -e "s|assets/css/style\.css|assets/css/style.${STYLE_HASH}.css|g" \
  {} \;

mv assets/css/style.css "assets/css/style.${STYLE_HASH}.css"

find . -type f \( -name "*.html" -o -name "*.css" -o -name "*.js" -o -name "*.svg" \) | \
  while IFS= read -r f; do
    gzip  -k -9    "$f"
    brotli -k -q 11 "$f"
  done
