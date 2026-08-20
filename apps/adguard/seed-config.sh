# shellcheck shell=sh
if [ "$(cat /conf/.template-hash 2>/dev/null)" != "$TEMPLATE_HASH" ]; then
  cp /template/AdGuardHome.yaml /conf/AdGuardHome.yaml
  printf '%s' "$TEMPLATE_HASH" > /conf/.template-hash
fi
