import Foundation

/// The local, authenticated inbound endpoints an embedded Xray runtime exposes.
///
/// The SOCKS inbound is what the application routes its own traffic (MTProto,
/// media fetchers, calls) through; `managed` call routing in tgcalls requires
/// the loopback + username/password shape of `socks`. The HTTP inbound exists
/// for potential web-content routing parity with the desktop client.
public struct VlessLocalInbound: Equatable {
    public var port: Int
    public var user: String
    public var password: String

    public init(port: Int, user: String, password: String) {
        self.port = port
        self.user = user
        self.password = password
    }
}

public enum VlessXrayConfig {
    /// Assembles a complete Xray configuration for `profile`, exposing two
    /// authenticated local inbounds, mirroring the reference desktop
    /// `VlessProfile::xrayConfig(socks, http)`.
    public static func configJSON(profile: VlessProfile, socks: VlessLocalInbound, http: VlessLocalInbound) -> String? {
        guard socks.port > 0, http.port > 0, socks.port != http.port,
              isValidLocalCredential(socks.user), isValidLocalCredential(socks.password),
              isValidLocalCredential(http.user), isValidLocalCredential(http.password) else {
            return nil
        }

        var user: [String: Any] = [
            "id": profile.userId,
            // "none" for legacy profiles, or the post-quantum
            // mlkem768x25519plus key expression carried by the share link.
            "encryption": profile.encryption,
        ]
        if !profile.flow.rawValue.isEmpty {
            user["flow"] = profile.flow.rawValue
        }

        var stream: [String: Any] = [
            "network": profile.transport.rawValue,
            "security": profile.security.rawValue,
        ]
        
        var sockopt: [String: Any] = [:]
        if let downFrame = profile.sockoptDownFrame {
            sockopt["downFrame"] = downFrame
        }
        if let scStream = profile.sockoptScStreamDownServerSecs {
            sockopt["scStreamDownServerSecs"] = scStream
        }
        if !sockopt.isEmpty {
            stream["sockopt"] = sockopt
        }
        switch profile.transport {
        case .tcp:
            break
        case .ws:
            var settings: [String: Any] = [
                "path": profile.path ?? "/",
            ]
            if let host = profile.transportHost {
                settings["host"] = host
            }
            stream["wsSettings"] = settings
        case .grpc:
            var settings: [String: Any] = [
                "serviceName": profile.grpcServiceName ?? "",
                "multiMode": profile.grpcMultiMode,
            ]
            if let authority = profile.grpcAuthority, !authority.isEmpty {
                settings["authority"] = authority
            }
            stream["grpcSettings"] = settings
        case .httpupgrade:
            var settings: [String: Any] = [
                "path": profile.path ?? "/",
            ]
            if let host = profile.transportHost {
                settings["host"] = host
            }
            stream["httpupgradeSettings"] = settings
        case .xhttp:
            var settings: [String: Any] = [
                "path": profile.path ?? "/",
            ]
            if let host = profile.transportHost {
                settings["host"] = host
            }
            if let mode = profile.xhttpMode {
                settings["mode"] = mode
            }
            // The `extra` object is merged into xhttpSettings by the core;
            // top-level path/host/mode take priority over its contents.
            if let extraJSON = profile.xhttpExtraJSON, let extraData = extraJSON.data(using: .utf8), let extraObject = (try? JSONSerialization.jsonObject(with: extraData, options: [])) as? [String: Any] {
                settings["extra"] = extraObject
            }
            stream["xhttpSettings"] = settings
        }

        switch profile.security {
        case .none:
            break
        case .tls:
            var settings: [String: Any] = [
                "allowInsecure": profile.allowInsecure,
            ]
            if let serverName = profile.serverName {
                settings["serverName"] = serverName
            }
            if let fingerprint = profile.fingerprint {
                settings["fingerprint"] = fingerprint.rawValue
            }
            if !profile.alpn.isEmpty {
                settings["alpn"] = profile.alpn
            }
            stream["tlsSettings"] = settings
        case .reality:
            guard let publicKey = profile.publicKey else {
                return nil
            }
            var settings: [String: Any] = [
                "publicKey": publicKey,
                "allowInsecure": profile.allowInsecure,
            ]
            if let serverName = profile.serverName {
                settings["serverName"] = serverName
            }
            if let fingerprint = profile.fingerprint {
                settings["fingerprint"] = fingerprint.rawValue
            }
            if let shortId = profile.shortId {
                settings["shortId"] = shortId
            }
            if let spiderX = profile.spiderX {
                settings["spiderX"] = spiderX
            }
            stream["realitySettings"] = settings
        }

        let root: [String: Any] = [
            "log": [
                "access": "none",
                "loglevel": "warning",
            ],
            "inbounds": [
                [
                    "tag": "telegram-socks",
                    "listen": "127.0.0.1",
                    "port": socks.port,
                    "protocol": "socks",
                    "settings": [
                        "auth": "password",
                        "accounts": [
                            ["user": socks.user, "pass": socks.password],
                        ],
                        "udp": true,
                    ],
                ],
                [
                    "tag": "telegram-web",
                    "listen": "127.0.0.1",
                    "port": http.port,
                    "protocol": "http",
                    "settings": [
                        "accounts": [
                            ["user": http.user, "pass": http.password],
                        ],
                        "allowTransparent": false,
                    ],
                ],
            ],
            "outbounds": [
                [
                    "tag": "vless-out",
                    "protocol": "vless",
                    "settings": [
                        "vnext": [
                            [
                                "address": profile.endpoint.host,
                                "port": profile.endpoint.port,
                                "users": [user],
                            ],
                        ],
                    ],
                    "streamSettings": stream,
                ],
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func isValidLocalCredential(_ value: String) -> Bool {
        return !value.isEmpty && value.count <= 255 && !value.contains("\0") && value.allSatisfy { $0.asciiValue != nil && $0.asciiValue! >= 0x21 && $0.asciiValue! <= 0x7e }
    }
}
