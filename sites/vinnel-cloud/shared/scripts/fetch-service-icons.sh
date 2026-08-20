#!/bin/sh
set -eu

dir="${1:?usage: fetch-service-icons.sh <target-dir>}"
mkdir -p "$dir"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

fetch() {
  curl -fsSL -A "$UA" "$2" -o "$dir/$1"
}

fetch satisfactory.png https://www.satisfactorygame.com/apple-touch-icon.png
fetch minecraft.jpg https://www.minecraft.net/content/dam/minecraftnet/franchise/logos/minecraft-creeper-face.jpg
fetch signoz.png https://signoz.io/static/favicons/favicon-96x96.png
fetch hubble.png https://cdn.jsdelivr.net/gh/cilium/hubble@main/Documentation/images/hubble_logo.png
fetch adguard.svg https://st2.adguardcdn.com/favicons/adguard/favicon.svg
fetch netbird.png https://netbird.io/icon.png
fetch seaweedfs.png https://seaweedfs.com/images/seaweed-logo.png
fetch nextcloud.png https://nextcloud.com/c/uploads/2022/03/favicon.png
fetch velero.ico https://velero.io/favicon.ico
