#!/bin/sh
set -eu

name="$1"
root=$(cd "$(dirname "$0")/../.." && pwd)

secrets=$(sops decrypt "$root/secrets.sops.json")
value=$(printf %s "$secrets" | jq -r --arg name "$name" '.[$name] // empty')
if [ -z "$value" ]; then
  value=$(sed -n "/^variable \"$name\"/,/^}/s/^ *default *= *\"\(.*\)\"/\1/p" "$root/hestia/variables.tf")
fi
if [ -z "$value" ]; then
  echo "$name is neither set in secrets.sops.json nor defaulted in hestia/variables.tf" >&2
  exit 1
fi
printf %s "$value"
