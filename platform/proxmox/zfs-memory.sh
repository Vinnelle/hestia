#!/bin/sh
set -eu

arc_max=2147483648
arc_min=536870912
dirty_max=536870912
min_free_kb=262144

printf 'options zfs zfs_arc_max=%s zfs_arc_min=%s zfs_dirty_data_max=%s\n' "$arc_max" "$arc_min" "$dirty_max" > /etc/modprobe.d/zfs.conf
echo "$arc_max" > /sys/module/zfs/parameters/zfs_arc_max
echo "$arc_min" > /sys/module/zfs/parameters/zfs_arc_min
echo "$dirty_max" > /sys/module/zfs/parameters/zfs_dirty_data_max
printf 'vm.min_free_kbytes = %s\n' "$min_free_kb" > /etc/sysctl.d/90-memory.conf
sysctl -q -p /etc/sysctl.d/90-memory.conf
update-initramfs -u -k all >/dev/null
echo "ZFS's ARC stays between $((arc_min >> 20)) and $((arc_max >> 20)) MiB, its write buffer under $((dirty_max >> 20)) MiB, and the kernel keeps $((min_free_kb >> 10)) MiB free, now and from every boot"
