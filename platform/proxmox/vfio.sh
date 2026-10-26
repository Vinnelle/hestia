#!/bin/sh
set -eu

cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio-pci ids=$VFIO_IDS disable_vga=1
softdep nouveau pre: vfio-pci
softdep snd_hda_intel pre: vfio-pci
EOF
printf '%s\n' 'blacklist nouveau' > /etc/modprobe.d/nouveau-blacklist.conf
printf '%s\n' vfio vfio_iommu_type1 vfio_pci > /etc/modules-load.d/vfio.conf
update-initramfs -u -k all >/dev/null

for dev in /sys/bus/pci/devices/"$PCI_PATH".*; do
  driver=$(readlink "$dev/driver" || true)
  echo "${dev##*/} is bound to ${driver##*/} until the next boot"
done
