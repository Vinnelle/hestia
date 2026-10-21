#!/bin/sh
set -eu

wget -q -O /run/node.key "$FILES/node.key"
ip link add wg0 type wireguard
wg set wg0 private-key /run/node.key peer "$(wget -q -O - "$FILES/relay.pub")" endpoint "$RELAY_ENDPOINT" \
  allowed-ips 10.88.0.1/32 persistent-keepalive 5
rm -f /run/node.key
ip address add 10.88.0.2/24 dev wg0
ip link set wg0 up

cat > /usr/local/bin/hello <<'EOF'
#!/bin/sh
cr=$(printf '\r')
while read -r line && [ -n "${line%"$cr"}" ]; do :; done
printf 'HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 20\r\n\r\nhello from the node\n'
EOF
chmod 0755 /usr/local/bin/hello
for port in 80 443; do
  nc -lk -s 10.88.0.2 -p "$port" -e /usr/local/bin/hello &
done

sa=/var/run/secrets/kubernetes.io/serviceaccount
mkdir -p "$sa" /tmp/blog /tmp/media
wget -q -O "$sa/ca.crt" "$FILES/kube.crt"
printf 'local-dev-token\n' > "$sa/token"
wget -q -O /usr/local/bin/admin "$FILES/admin"
chmod 0755 /usr/local/bin/admin

env KUBERNETES_SERVICE_HOST="${KUBE_ENDPOINT%:*}" KUBERNETES_SERVICE_PORT="${KUBE_ENDPOINT#*:}" \
  LISTEN_ADDR=0.0.0.0:8080 BLOG_DATA_DIR=/tmp/blog BLOG_MEDIA_DIR=/tmp/media \
  RELAY_METRICS_URL=http://10.88.0.1:9100/metrics RELAY_LOCATION="local QEMU" NODE_LOCATION="mock Talos node" \
  /usr/local/bin/admin > /dev/console 2>&1 &

echo "node: wg0 up, dashboard on :8080" > /dev/console
