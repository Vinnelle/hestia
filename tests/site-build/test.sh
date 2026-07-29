#!/usr/bin/env bash
# Unit test for the (identical) hash_and_rewrite/precompress logic shared by
# monke-academy/vin-moe/vinnel-cloud's site/build.sh. cleancss/terser/brotli
# are shimmed as no-ops so this needs no real minifier/compressor installed —
# only hash_and_rewrite's sed-rewrite correctness and precompress's file
# creation are under test, not the third-party tools.
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
# brotli -k -q 11 FILE writes FILE.br; a bare `true` shim would silently skip
# that, so precompress()'s own contract (a .br sidecar exists) goes untested.
# Real invocation only ever passes one file (the last arg); flags come first.
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

for rel in monke-academy vin-moe vinnel-cloud; do
  test_one "$repo_root/hestia/$rel/site/build.sh"
done

exit "$fail"
