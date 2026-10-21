#!/bin/sh
set -eu

version=3.24.2
branch=v3.24
iso_sha256=3ab424762af704b2c2a9e57df1dc37f982af260071504d977f2fb96822e7130b
cmdline="console=tty0 console=ttyS0,115200 ipv6.disable=1 init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 slab_nomerge randomize_kstack_offset=on vsyscall=none debugfs=off"

case "$(cat /etc/alpine-release 2>/dev/null)" in
  "${branch#v}".*) ;;
  *) echo "build.sh runs inside an alpine:${branch#v} container" >&2; exit 1 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
out="$here/out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mirror="https://dl-cdn.alpinelinux.org/alpine/$branch"
iso="alpine-virt-$version-x86_64.iso"

echo "==> installing build tools"
apk add --no-cache --quiet tar xorriso

echo "==> downloading $iso"
wget -q -O "$work/$iso" "$mirror/releases/x86_64/$iso"
echo "$iso_sha256  $work/$iso" | sha256sum -c -

echo "==> fetching signed packages from $branch"
mkdir -p "$work/relay/apks"
apk fetch --quiet --update-cache --recursive \
  --repositories-file /dev/null --repository "$mirror/main" --repository "$mirror/community" \
  --output "$work/relay/apks" iproute2-minimal nftables prometheus-node-exporter wireguard-tools-wg
for apk in "$work/relay/apks"/*.apk; do
  echo "    $(basename "$apk" .apk)"
done

echo "==> packing the overlay ($(find "$here/overlay" -type f | wc -l) files)"
tar -C "$here/overlay" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - . \
  | gzip -9n > "$work/relay.apkovl.tar.gz"

echo "==> adding the hardened kernel command line"
xorriso -osirrox on -indev "$work/$iso" \
  -extract /boot/syslinux/syslinux.cfg "$work/syslinux.cfg" \
  -extract /boot/grub/grub.cfg "$work/grub.cfg" 2>/dev/null
chmod u+w "$work/syslinux.cfg" "$work/grub.cfg"
sed -i "s|^APPEND .*|& $cmdline|" "$work/syslinux.cfg"
sed -i "s|^linux[[:space:]].*|& $cmdline|" "$work/grub.cfg"
grep -q 'ipv6.disable=1' "$work/syslinux.cfg"
grep -q 'ipv6.disable=1' "$work/grub.cfg"

echo "==> writing the image"
mkdir -p "$out"
rm -f "$out/relay.img" "$out/relay.img.sha256"
xorriso -indev "$work/$iso" -outdev "$out/relay.img" \
  -map "$work/relay.apkovl.tar.gz" /relay.apkovl.tar.gz \
  -map "$work/relay" /relay \
  -map "$work/syslinux.cfg" /boot/syslinux/syslinux.cfg \
  -map "$work/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay -boot_image any system_area=/dev/zero -boot_image any partition_table=off 2>/dev/null
sha256sum "$out/relay.img" | cut -d' ' -f1 > "$out/relay.img.sha256"
chown -R "$(stat -c %u:%g "$here")" "$out"
echo "built $out/relay.img: $(du -m "$out/relay.img" | cut -f1) MiB, sha256 $(cat "$out/relay.img.sha256")"
