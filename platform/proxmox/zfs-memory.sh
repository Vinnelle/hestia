#!/bin/sh
set -eu

arc_max=2147483648
dirty_max=536870912

printf 'options zfs zfs_arc_max=%s zfs_dirty_data_max=%s\n' "$arc_max" "$dirty_max" > /etc/modprobe.d/zfs.conf
echo "$arc_max" > /sys/module/zfs/parameters/zfs_arc_max
echo "$dirty_max" > /sys/module/zfs/parameters/zfs_dirty_data_max
update-initramfs -u -k all >/dev/null
echo "ZFS's ARC is capped at $((arc_max >> 20)) MiB and its write buffer at $((dirty_max >> 20)) MiB, now and from every boot"
