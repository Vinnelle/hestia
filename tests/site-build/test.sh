#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail=0
ok()  { echo "ok: $1"; }
bad() { echo "FAIL: $1" >&2; fail=1; }

shim_dir="$(mktemp -d)"
trap 'rm -rf "$shim_dir"' EXIT
for tool in cleancss terser; do
  printf '#!/bin/sh\ntrue\n' >"$shim_dir/$tool"
  chmod +x "$shim_dir/$tool"
done
printf '#!/bin/sh\neval f=\\"\\${$#}\\"\ncp "$f" "$f.br"\n' >"$shim_dir/brotli"
chmod +x "$shim_dir/brotli"
export PATH="$shim_dir:$PATH"

test_one() {
  script="$1"
  work="$(mktemp -d)"

  mkdir -p "$work/css"
  printf 'body{color:red}' >"$work/css/site.css"
  printf 'console.log(1)' >"$work/app.js"
  cat >"$work/index.html" <<'EOF'
<link rel="stylesheet" href="/css/site.css">
<script src="app.js"></script>
EOF

  ( cd "$work" && sh "$script" ) >/dev/null

  new_css="$(find "$work/css" -name 'site.*.css')"
  new_js="$(find "$work" -maxdepth 1 -name 'app.*.js')"

  if [ -n "$new_css" ]; then ok "$script: css renamed to a hashed filename"
  else bad "$script: css was not renamed to a hashed filename"; fi

  if [ -n "$new_js" ]; then ok "$script: js renamed to a hashed filename"
  else bad "$script: js was not renamed to a hashed filename"; fi

  if [ -n "$new_css" ] && [ -n "$new_js" ]; then
    new_css_rel="${new_css#"$work"/}"
    new_js_rel="${new_js#"$work"/}"

    if grep -qF "/$new_css_rel" "$work/index.html"; then
      ok "$script: absolute-path href rewritten to hashed css"
    else bad "$script: absolute-path href was not rewritten"; fi

    if grep -qF "$new_js_rel" "$work/index.html"; then
      ok "$script: relative script src rewritten to hashed js"
    else bad "$script: relative script src was not rewritten"; fi

    if [ -f "$new_css.gz" ] && [ -f "$new_css.br" ]; then
      ok "$script: hashed css precompressed (gzip+brotli)"
    else bad "$script: hashed css missing .gz/.br sidecar"; fi
  fi

  rm -rf "$work"
}

for rel in monke-academy/site/build.sh \
           vin-moe/site/scripts/build.sh \
           vinnel-cloud/site/scripts/build.sh \
           vinnel-cloud/auth/scripts/build.sh \
           vinnel-cloud/admin/scripts/build.sh; do
  test_one "$repo_root/hestia/$rel"
done

exit "$fail"
