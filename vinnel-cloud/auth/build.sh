#!/bin/sh
set -eu

minify_css() {
  find . -type f -name '*.css' ! -name '*.min.css' | while IFS= read -r f; do
    cleancss -O2 -o "$f" "$f"
  done
}

minify_js() {
  find . -type f -name '*.js' ! -name '*.min.js' | while IFS= read -r f; do
    terser "$f" --compress --mangle -o "$f"
  done
}

hash_and_rewrite() {
  map_file="$(mktemp)"

  find . -type f \( -name '*.css' -o -name '*.js' \) | while IFS= read -r f; do
    rel="${f#./}"
    dir="$(dirname "$rel")"
    base="$(basename "$rel")"
    stem="${base%.*}"
    ext="${base##*.}"
    hash="$(md5sum "$f" | cut -c1-8)"
    new_rel="${dir}/${stem}.${hash}.${ext}"
    printf '%s|%s\n' "$rel" "$new_rel" >> "$map_file"
  done

  if [ -s "$map_file" ]; then
    while IFS='|' read -r old_rel new_rel; do
      old_escaped="$(printf '%s\n' "$old_rel" | sed 's/[.[\*^$()+?{}|\/]/\\&/g')"
      find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.php' \) -exec sed -i \
        -e "s|${old_escaped}|${new_rel}|g" \
        -e "s|/${old_escaped}|/${new_rel}|g" \
        {} \;
    done < "$map_file"

    while IFS='|' read -r old_rel new_rel; do
      mv "$old_rel" "$new_rel"
    done < "$map_file"
  fi

  rm -f "$map_file"
}

precompress() {
  find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.svg' -o -name '*.xml' -o -name '*.txt' -o -name '*.json' \) | \
    while IFS= read -r f; do
      gzip -k -9 "$f"
      brotli -k -q 11 "$f"
    done
}

minify_css
minify_js
hash_and_rewrite
precompress
