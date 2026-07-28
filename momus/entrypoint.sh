#!/bin/bash
set -euo pipefail

for binary in code kubectl love starship; do
  if ! command -v "$binary" &>/dev/null; then
    echo "missing required binary: $binary" >&2
    exit 1
  fi
done

chpasswd <<< "root:$(cat /run/passwords/root)"
chpasswd <<< "ida:$(cat /run/passwords/ida)"

install -d -m 755 -o ida -g ida /home/ida

install -d -m 700 -o ida -g ida /home/ida/.ssh
install -m 600 -o ida -g ida /run/authorized-keys/authorized_keys /home/ida/.ssh/authorized_keys

install -d -m 755 -o ida -g ida /home/ida/.config
install -m 644 -o ida -g ida /run/dotfiles/.zshrc /home/ida/.zshrc
install -m 644 -o ida -g ida /run/dotfiles/starship.toml /home/ida/.config/starship.toml

install -d -m 700 -o ida -g ida /home/ida/.kube
install -m 600 -o ida -g ida /etc/momus-kube/config /home/ida/.kube/config 2>/dev/null \
  || echo "warning: kubeconfig not mounted at /etc/momus-kube/config" >&2

chown ida:ida /home/ida/Projects 2>/dev/null || true

chown ida:ida /home/ida/.vscode-cli 2>/dev/null || true

install -d -m 700 /etc/ssh/host_keys
[ -f /etc/ssh/host_keys/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/host_keys/ssh_host_ed25519_key
[ -f /etc/ssh/host_keys/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -b 4096 -N "" -f /etc/ssh/host_keys/ssh_host_rsa_key

install -d -m 755 /run/sshd
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
