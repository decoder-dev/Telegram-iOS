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

# Some VPS networks have a broken IPv6 route (registry/CDN requests time out on an IPv6 address).
# Prefer IPv4 for name resolution so image pulls and downloads do not hang.
if ! grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null; then
  echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf
fi

pull_with_retry() {
  for attempt in 1 2 3 4 5; do
    docker pull "$1" >/dev/null && return 0
    echo "docker pull failed (attempt $attempt), retrying..." >&2
    sleep $((attempt * 3))
  done
  return 1
}

# Install Docker Engine from Docker's official apt repository
# (https://docs.docker.com/engine/install/ubuntu/ and /debian/).
install_docker() {
  . /etc/os-release
  case "$ID" in
    ubuntu|debian) ;;
    *) case "${ID_LIKE:-}" in
         *ubuntu*) ID=ubuntu ;;
         *debian*) ID=debian ;;
         *) echo "unsupported distro: $ID (need Debian or Ubuntu)" >&2; exit 1 ;;
       esac ;;
  esac
  CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  for old in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y "$old" >/dev/null 2>&1 || true
  done

  install -m 0755 -d /etc/apt/keyrings
  curl -4 -fsSL --retry 5 "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

if ! command -v docker >/dev/null 2>&1; then
  install_docker
fi
systemctl enable --now docker >/dev/null 2>&1 || true

mkdir -p "$DIR"
pull_with_retry nineseconds/mtg:2

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

IP="$(curl -4 -fsS https://api.ipify.org || hostname -I | awk '{print $1}')"
sleep 2
docker ps --filter "name=$NAME" --format '{{.Status}}'
echo
echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"
