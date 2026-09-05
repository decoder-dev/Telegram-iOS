# WEB proxy: SOCKS5 bridge for arbitrary stream targets

Status: **client side implemented, relay side is a spec**. The client is capability-gated and
inert against every relay built before this document — no relay change is required for anything
that exists today. This file is the contract a relay must implement to turn the bridge on.

## Why

tgcalls cannot speak MTProto, so an active WEB proxy used to leave calls direct — a
traffic-analysis hole in the "everything through the proxy" posture (`docs/network-audit.md`,
F-1). The sidecar already multiplexes arbitrary streams over the carrier; the missing piece was
(1) letting the relay dial a host:port other than its own backing MTProxy, and (2) exposing that
dialer to SOCKS5-only consumers through a local SOCKS5 endpoint.

## Capability negotiation (WELCOME payload, v1)

The WELCOME frame's payload was previously ignored by the client; it is now parsed as:

```
version : 1 byte, 0x01
flags   : 1 byte, OPTIONAL (absent = 0x00)
```

* Bit 0 of `flags` — `arbitraryStreamTargets`: the relay accepts OPEN frames that name a
  target (below).
* All other bits: reserved, must be ignored by unknown clients.

An empty or one-byte payload means "no capabilities" — exactly the behavior of every existing
relay, which is what makes the extension backwards compatible in both directions.

The client reads the capability **live, at the moment a SOCKS CONNECT is accepted** — a WELCOME
that arrives after an empty-bodied session response must not be missed, and a carrier reconnect
resets it automatically (new carrier, fresh WELCOME).

## OPEN with a target

With the capability present, an OPEN's payload is the connect request — same address encoding
as SOCKS5 (RFC 1928 §4, DST.ADDR/DST.PORT):

```
atyp : 1 byte — 0x01 IPv4 | 0x03 domain | 0x04 IPv6
addr : 4 bytes (IPv4) | 1 + len bytes (domain, len ≤ 255) | 16 bytes (IPv6)
port : 2 bytes, big endian
```

An OPEN with an **empty** payload keeps its legacy meaning: connect to the relay's backing
MTProxy. MTProto bootstrap continues to use it unchanged.

Failure to dial is reported by a `CLOSE` frame on that stream. The local SOCKS client sees a
dropped connection after a successful CONNECT reply — the same failure mode as an unreachable
direct target, so client-side failover logic stays intact.

## Local endpoint (client side)

`WebProxySidecar` runs a second `NWListener` alongside the MTProxy one:

* **Loopback only** (`requiredLocalEndpoint` = 127.0.0.1). The main MTProxy listener is
  unchanged and still binds all interfaces — it is secret-protected and part of the tested
  bootstrap; churning it for this feature is not worth the risk.
* **Authentication required**: method `0x02` (username/password, RFC 1929) only; a client
  offering no-auth gets `[0x05, 0xFF]` and a disconnect. This is not paranoia: iOS does not
  isolate loopback between apps, and this listener dials arbitrary targets through the user's
  relay. Credentials are random per sidecar start (16 bytes, hex) and are never persisted.
* The listener starts with the sidecar and survives carrier reconnects (like the main port);
  CONNECTs are refused while the relay has not advertised the capability, and after a listener
  bind failure the bridge is simply absent — nothing else degrades.

Consumer path: `WebProxyManager.activeSocksBridgeEndpoint` →
`webProxySidecarCallProxySettings()` (TelegramCore) → `PresentationCallManager
.resolvedCallProxyServer()`. A WEB proxy resolves to the bridge SOCKS5 settings for calls when
the capability is up, and to **direct** (nil) when it is not — a missing bridge must never fail
a call. Calls resolve this at call-creation time, not from the settings subscription, because
the sidecar can become ready after the settings change.

## Security notes for the relay

* The relay dials **exactly** what the SOCKS client asked for — no redirect table, no
  interpretation. The trust anchor is the bridge token the client already presented at session
  creation (`WebProxyBridgeCapability`, HMAC-SHA256 over the hostname); the capability bit
  merely widens what the relay is willing to dial for an already-authenticated session.
* A relay MAY restrict target hosts/ports (its own policy); a refused dial is a `CLOSE`, not a
  session error.
* Per-stream windows, keepalive and `BYE` semantics are unchanged — a target-bearing stream is
  an ordinary stream once the OPEN is accepted.

## What is intentionally NOT in v1

* UDP ASSOCIATE, BIND — tgcalls needs neither.
* Advertising the bridge to the app in any UI. The calls screen shows a disclaimer
  (`ForkWebProxyStrings.callsNote`) instead: the bridge depends on relay support.
