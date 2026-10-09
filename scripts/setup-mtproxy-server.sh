#!/usr/bin/env bash
# Set up a Fake-TLS MTProxy (mtg v2) on a fresh Debian/Ubuntu VPS for the BananaGram client.
#
# The client speaks stock MTProxy, including the Fake-TLS ("ee" secret) handshake with SNI,
# so no client-side changes are needed: add the printed tg://proxy link in Settings > Data and Storage > Proxy.
#
# Usage (as root):  bash setup-mtproxy-server.sh [PORT] [FAKE_TLS_DOMAIN]
#   PORT             public port, default 443
#   FAKE_TLS_DOMAIN  real HTTPS site that unauthenticated probes are forwarded to, default storage.googleapis.com
set -euo pipefail

PORT="${1:-443}"
DOMAIN="${2:-storage.googleapis.com}"
NAME=mtg
DIR=/opt/mtg

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker.io curl
  systemctl enable --now docker
fi

mkdir -p "$DIR"
docker pull nineseconds/mtg:2 >/dev/null

if [ ! -s "$DIR/secret" ]; then
  docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN" > "$DIR/secret"
fi
SECRET="$(tr -d '\n' < "$DIR/secret")"

cat > "$DIR/config.toml" <<TOML
secret = "$SECRET"
bind-to = "0.0.0.0:3128"
prefer-ip = "prefer-ipv4"
domain-fronting-port = 443
tolerate-time-skewness = "5s"

[network]
doh-ip = "1.1.1.1"
TOML

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart always \
  -p "$PORT:3128" \
  -v "$DIR/config.toml:/config.toml:ro" \
  nineseconds/mtg:2 run /config.toml >/dev/null

# Firewall + TCP tuning (best effort).
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "$PORT/tcp" >/dev/null
fi
grep -q 'tcp_congestion_control=bbr' /etc/sysctl.d/99-mtproxy.conf 2>/dev/null || {
  printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-mtproxy.conf
  sysctl --system >/dev/null 2>&1 || true
}

IP="$(curl -fsS4 https://api.ipify.org || hostname -I | awk '{print $1}')"
sleep 2
docker ps --filter "name=$NAME" --format '{{.Status}}'
echo
echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"
