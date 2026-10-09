#!/usr/bin/env bash
# Set up a Fake-TLS MTProxy (mtg v2, plain binary + systemd, no Docker) on a Linux VPS for the BananaGram client.
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
DIR=/etc/mtg
BIN=/usr/local/bin/mtg
FALLBACK_VERSION=2.2.8

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# Prefer IPv4: some VPS networks have a broken IPv6 route and downloads stall on it.
grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null || echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

step "checking the system"
case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  armv7l)        ARCH=armv7 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl ca-certificates; }
command -v systemctl >/dev/null 2>&1 || { echo "systemd is required" >&2; exit 1; }

step "downloading mtg"
TAG="$(curl -4 -fsSL -m 20 -o /dev/null -w '%{url_effective}' https://github.com/9seconds/mtg/releases/latest 2>/dev/null | sed 's|.*/tag/v||' || true)"
case "$TAG" in [0-9]*.[0-9]*.[0-9]*) ;; *) TAG="$FALLBACK_VERSION" ;; esac
echo "version $TAG, linux-$ARCH"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL="https://github.com/9seconds/mtg/releases/download/v${TAG}/mtg-${TAG}-linux-${ARCH}.tar.gz"
curl -4 -fL --retry 5 --retry-delay 3 --connect-timeout 15 -m 180 "$URL" -o "$TMP/mtg.tar.gz"
tar -xzf "$TMP/mtg.tar.gz" -C "$TMP"
FOUND="$(find "$TMP" -type f -name mtg | head -1)"
[ -n "$FOUND" ] || { echo "mtg binary not found in the archive" >&2; exit 1; }
install -m 0755 "$FOUND" "$BIN"
"$BIN" --version || true

step "generating the secret"
mkdir -p "$DIR"
if [ ! -s "$DIR/secret" ] || ! grep -q . "$DIR/secret"; then
  "$BIN" generate-secret --hex "$DOMAIN" > "$DIR/secret"
  chmod 600 "$DIR/secret"
fi
SECRET="$(tr -d '\n' < "$DIR/secret")"

cat > "$DIR/config.toml" <<TOML
secret = "$SECRET"
bind-to = "0.0.0.0:$PORT"
prefer-ip = "prefer-ipv4"
tolerate-time-skewness = "5s"
TOML
chmod 600 "$DIR/config.toml"

step "starting the service"
cat > /etc/systemd/system/mtg.service <<UNIT
[Unit]
Description=mtg MTProxy (Fake-TLS)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BIN run $DIR/config.toml
Restart=always
RestartSec=3
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable mtg >/dev/null 2>&1
systemctl restart mtg
sleep 2
systemctl is-active mtg || { journalctl -u mtg --no-pager -n 20; exit 1; }

step "firewall and TCP tuning"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "$PORT/tcp" >/dev/null
fi
if [ ! -f /etc/sysctl.d/99-mtproxy.conf ]; then
  printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-mtproxy.conf
  sysctl --system >/dev/null 2>&1 || true
fi

IP="$(curl -4 -fsS -m 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
echo
echo "Done. Add this proxy in the client:"
echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"
