import Foundation

/// A parsed and validated `vless://` share-link profile.
///
/// The parameter space mirrors the strict allowlist of the reference desktop
/// integration (telegramvless `Core::ParseVlessProfile`), extended for the
/// modern Xray link surface: the XHTTP transport (`type=xhttp` with `mode`,
/// `extra`), the post-quantum `mlkem768x25519plus` encryption layer, and the
/// `allowInsecure` flag. Anything outside the supported subset is rejected
/// instead of silently ignored, so a profile that parses here is guaranteed to
/// be fully expressible in the generated Xray configuration.
public struct VlessProfile: Equatable {
    public enum Flow: String, Equatable {
        case none = ""
        case xtlsRprxVision = "xtls-rprx-vision"
    }

    public enum Security: String, Equatable {
        case none
        case tls
        case reality
    }

    public enum Transport: String, Equatable {
        case tcp
        case ws = "websocket"
        case grpc
        case httpupgrade
        case xhttp
    }

    public enum Fingerprint: String, Equatable {
        case chrome
        case firefox
        case safari
        case ios
        case android
        case edge
        case random
        case randomized
    }

    public struct Endpoint: Equatable {
        public var host: String
        public var port: Int
    }

    public var endpoint: Endpoint
    public var userId: String
    public var flow: Flow
    public var security: Security
    public var transport: Transport

    // TLS / REALITY
    public var serverName: String?
    public var fingerprint: Fingerprint?
    public var alpn: [String]
    public var publicKey: String?
    public var shortId: String?
    public var spiderX: String?

    // Transport settings
    public var path: String?
    public var transportHost: String?
    public var grpcServiceName: String?
    public var grpcAuthority: String?
    public var grpcMultiMode: Bool

    // XHTTP settings
    public var xhttpMode: String?
    public var xhttpExtraJSON: String?

    // Sockopt / Mux overrides
    public var sockoptDownFrame: Int?
    public var sockoptScStreamDownServerSecs: Int?

    // VLESS encryption layer: "none", or a post-quantum
    // mlkem768x25519plus key expression passed through verbatim to the core.
    public var encryption: String

    // TLS/REALITY: skip server certificate verification (allowInsecure in share links).
    public var allowInsecure: Bool

    public init(
        endpoint: Endpoint,
        userId: String,
        flow: Flow,
        security: Security,
        transport: Transport,
        serverName: String? = nil,
        fingerprint: Fingerprint? = nil,
        alpn: [String] = [],
        publicKey: String? = nil,
        shortId: String? = nil,
        spiderX: String? = nil,
        path: String? = nil,
        transportHost: String? = nil,
        grpcServiceName: String? = nil,
        grpcAuthority: String? = nil,
        grpcMultiMode: Bool = false,
        encryption: String = "none",
        allowInsecure: Bool = false,
        xhttpMode: String? = nil,
        xhttpExtraJSON: String? = nil,
        sockoptDownFrame: Int? = nil,
        sockoptScStreamDownServerSecs: Int? = nil
    ) {
        self.endpoint = endpoint
        self.userId = userId
        self.flow = flow
        self.security = security
        self.transport = transport
        self.serverName = serverName
        self.fingerprint = fingerprint
        self.alpn = alpn
        self.publicKey = publicKey
        self.shortId = shortId
        self.spiderX = spiderX
        self.path = path
        self.transportHost = transportHost
        self.grpcServiceName = grpcServiceName
        self.grpcAuthority = grpcAuthority
        self.grpcMultiMode = grpcMultiMode
        self.encryption = encryption
        self.allowInsecure = allowInsecure
        self.xhttpMode = xhttpMode
        self.xhttpExtraJSON = xhttpExtraJSON
        self.sockoptDownFrame = sockoptDownFrame
        self.sockoptScStreamDownServerSecs = sockoptScStreamDownServerSecs
    }
}

public enum VlessProfileError: Error, Equatable {
    case empty
    case tooLong
    case invalidUri
    case invalidUserId
    case invalidHost
    case invalidPort
    case duplicateParameter
    case unsupportedParameter(String)
    case unsupportedEncryption(String)
    case unsupportedFlow(String)
    case unsupportedTransport(String)
    case unsupportedHeaderType(String)
    case unsupportedSecurity(String)
    case unsupportedFingerprint(String)
    case invalidAlpn(String)
    case invalidPublicKey
    case invalidShortId
    case invalidServerName
    case missingRealityPublicKey
    case invalidQuery
    case invalidExtra
    case invalidAllowInsecure
}

private let allowedParameters: Set<String> = [
    "encryption", "flow", "security", "sni", "fp", "alpn", "pbk", "sid", "spx",
    "type", "host", "path", "serviceName", "mode", "authority",
    "extra", "allowInsecure", "downFrame", "scStreamDownServerSecs"
]

public enum VlessProfileParser {
    // A post-quantum mlkem768x25519plus key expression alone is ~1.6 KB, and the
    // XHTTP `extra` JSON adds several hundred more, so the cap must comfortably
    // exceed the classical 4 KB while still bounding the input.
    public static let maximumUriLength = 8192

    public static func parse(_ raw: String) -> Result<VlessProfile, VlessProfileError> {
        let uri = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if uri.isEmpty {
            return .failure(.empty)
        }
        if uri.count > maximumUriLength {
            return .failure(.tooLong)
        }
        guard uri.lowercased().hasPrefix("vless://"), let url = URLComponents(string: uri), let host = url.host, let port = url.port else {
            return .failure(.invalidUri)
        }
        guard let user = url.user, Self.isValidUUID(user) else {
            return .failure(.invalidUserId)
        }
        if host.isEmpty || host.count > 255 || host.contains(" ") || host.contains("\0") || host.contains("/") {
            return .failure(.invalidHost)
        }
        if port < 1 || port > 65535 {
            return .failure(.invalidPort)
        }

        var query: [String: String] = [:]
        if let items = url.queryItems {
            for item in items {
                let name = item.name
                guard allowedParameters.contains(name) else {
                    return .failure(.unsupportedParameter(name))
                }
                if query[name] != nil {
                    return .failure(.duplicateParameter)
                }
                query[name] = item.value ?? ""
            }
        }

        // encryption: legacy VLESS uses "none"; the post-quantum layer (Xray v25.9.1+)
        // carries `mlkem768x25519plus.<native|xorpub|random>.<1rtt|0rtt>.<key>` in the
        // share link and in the outbound user settings. The key expression is passed
        // through verbatim - the core validates the key material itself.
        let encryptionRaw = query["encryption"].flatMap { $0.isEmpty ? nil : $0 } ?? "none"
        let encryption = encryptionRaw.lowercased() == "none" ? "none" : encryptionRaw
        guard encryption == "none" || Self.isValidVlessEncryption(encryption) else {
            return .failure(.unsupportedEncryption(encryptionRaw))
        }

        // flow
        let rawFlow = query["flow"] ?? ""
        let flow: VlessProfile.Flow
        switch rawFlow {
        case "":
            flow = .none
        case VlessProfile.Flow.xtlsRprxVision.rawValue:
            flow = .xtlsRprxVision
        default:
            return .failure(.unsupportedFlow(rawFlow))
        }

        // security
        let rawSecurity = (query["security"] ?? "none").lowercased()
        let security: VlessProfile.Security
        switch rawSecurity {
        case "none":
            security = .none
        case "tls":
            security = .tls
        case "reality":
            security = .reality
        default:
            return .failure(.unsupportedSecurity(rawSecurity))
        }

        // transport
        let rawTransport = (query["type"] ?? "tcp").lowercased()
        let transport: VlessProfile.Transport
        switch rawTransport {
        case "tcp":
            transport = .tcp
        case "ws", "websocket":
            transport = .ws
        case "grpc":
            transport = .grpc
        case "httpupgrade":
            transport = .httpupgrade
        case "xhttp", "splithttp":
            transport = .xhttp
        default:
            return .failure(.unsupportedTransport(rawTransport))
        }

        // fingerprint
        var fingerprint: VlessProfile.Fingerprint?
        if let rawFingerprint = query["fp"], !rawFingerprint.isEmpty {
            guard let value = VlessProfile.Fingerprint(rawValue: rawFingerprint.lowercased()) else {
                return .failure(.unsupportedFingerprint(rawFingerprint))
            }
            fingerprint = value
        }

        // alpn
        var alpn: [String] = []
        if let rawAlpn = query["alpn"], !rawAlpn.isEmpty {
            let parts = rawAlpn.split(separator: ",").map { String($0).lowercased() }
            for part in parts {
                guard part == "h2" || part == "http/1.1" else {
                    return .failure(.invalidAlpn(part))
                }
            }
            alpn = parts
        }

        // allowInsecure: links generated by modern clients always carry the flag;
        // anything but a recognized boolean form is rejected rather than guessed.
        var allowInsecure = false
        if let rawAllowInsecure = query["allowInsecure"], !rawAllowInsecure.isEmpty {
            switch rawAllowInsecure.lowercased() {
            case "0", "false":
                allowInsecure = false
            case "1", "true":
                allowInsecure = true
            default:
                return .failure(.invalidAllowInsecure)
            }
        }

        // serverName
        var serverName: String?
        if let rawServerName = query["sni"], !rawServerName.isEmpty {
            guard rawServerName.count <= 255, !rawServerName.contains(" "), !rawServerName.contains("\0") else {
                return .failure(.invalidServerName)
            }
            serverName = rawServerName
        }

        // REALITY
        var publicKey: String?
        var shortId: String?
        var spiderX: String?
        if security == .reality {
            guard let rawPublicKey = query["pbk"], !rawPublicKey.isEmpty, Self.isBase64URLString(rawPublicKey), rawPublicKey.count >= 43, rawPublicKey.count <= 44 else {
                return .failure(.invalidPublicKey)
            }
            publicKey = rawPublicKey
            if let rawShortId = query["sid"], !rawShortId.isEmpty {
                guard rawShortId.count <= 16, rawShortId.allSatisfy({ $0.isHexDigit }) else {
                    return .failure(.invalidShortId)
                }
                shortId = rawShortId
            }
            if let rawSpiderX = query["spx"], !rawSpiderX.isEmpty {
                spiderX = rawSpiderX
            }
        } else {
            for key in ["pbk", "sid", "spx"] where query[key] != nil && !(query[key]?.isEmpty ?? true) {
                return .failure(.unsupportedParameter(key))
            }
        }
        if security == .tls {
            // REALITY parameters make no sense over plain TLS.
            for key in ["pbk", "sid", "spx"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
        }

        // Transport settings
        var path: String?
        var transportHost: String?
        var grpcServiceName: String?
        var grpcAuthority: String?
        var grpcMultiMode = false
        var xhttpMode: String?
        var xhttpExtraJSON: String?
        switch transport {
        case .tcp:
            for key in ["path", "host", "serviceName", "mode", "authority", "extra"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
        case .ws, .httpupgrade:
            if let rawPath = query["path"], !rawPath.isEmpty {
                path = rawPath
            }
            if let rawHost = query["host"], !rawHost.isEmpty {
                transportHost = rawHost
            }
            for key in ["serviceName", "mode", "authority", "extra"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
        case .grpc:
            if let rawServiceName = query["serviceName"], !rawServiceName.isEmpty {
                grpcServiceName = rawServiceName
            } else {
                grpcServiceName = ""
            }
            if let rawMode = query["mode"], !rawMode.isEmpty {
                switch rawMode {
                case "gun", "multi":
                    grpcMultiMode = rawMode == "multi"
                default:
                    return .failure(.unsupportedParameter("mode"))
                }
            }
            if let rawAuthority = query["authority"], !rawAuthority.isEmpty {
                grpcAuthority = rawAuthority
            }
            for key in ["path", "host", "extra"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
        case .xhttp:
            if let rawPath = query["path"], !rawPath.isEmpty {
                path = rawPath
            }
            if let rawHost = query["host"], !rawHost.isEmpty {
                transportHost = rawHost
            }
            if let rawMode = query["mode"], !rawMode.isEmpty {
                switch rawMode {
                case "auto", "packet-up", "stream-up", "stream-one":
                    xhttpMode = rawMode
                default:
                    return .failure(.unsupportedParameter("mode"))
                }
            }
            if let rawExtra = query["extra"], !rawExtra.isEmpty {
                guard let extraJSON = Self.decodeXhttpExtra(rawExtra) else {
                    return .failure(.invalidExtra)
                }
                xhttpExtraJSON = extraJSON
            }
            for key in ["serviceName", "authority"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
        }

        // Sockopt
        var sockoptDownFrame: Int?
        if let rawDownFrame = query["downFrame"], !rawDownFrame.isEmpty {
            sockoptDownFrame = Int(rawDownFrame)
        }
        var sockoptScStreamDownServerSecs: Int?
        if let rawScStream = query["scStreamDownServerSecs"], !rawScStream.isEmpty {
            sockoptScStreamDownServerSecs = Int(rawScStream)
        }

        return .success(VlessProfile(
            endpoint: VlessProfile.Endpoint(host: host, port: port),
            userId: user,
            flow: flow,
            security: security,
            transport: transport,
            serverName: serverName,
            fingerprint: fingerprint,
            alpn: alpn,
            publicKey: publicKey,
            shortId: shortId,
            spiderX: spiderX,
            path: path,
            transportHost: transportHost,
            grpcServiceName: grpcServiceName,
            grpcAuthority: grpcAuthority,
            grpcMultiMode: grpcMultiMode,
            encryption: encryption,
            allowInsecure: allowInsecure,
            xhttpMode: xhttpMode,
            xhttpExtraJSON: xhttpExtraJSON,
            sockoptDownFrame: sockoptDownFrame,
            sockoptScStreamDownServerSecs: sockoptScStreamDownServerSecs
        ))
    }

    /// `mlkem768x25519plus.<native|xorpub|random>.<1rtt|0rtt>.<base64url key material>`,
    /// mirroring the acceptance rules of Xray-core's VLESS outbound configuration:
    /// at least four dot-separated parts, a known KEM/implementation/RTT triple,
    /// and key material limited to base64url characters and a sane length. The
    /// core performs the full cryptographic validation when the tunnel starts.
    static func isValidVlessEncryption(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, parts[0] == "mlkem768x25519plus" else {
            return false
        }
        guard ["native", "xorpub", "random"].contains(parts[1]) else {
            return false
        }
        guard ["1rtt", "0rtt"].contains(parts[2]) else {
            return false
        }
        let keyMaterial = parts[3...].joined(separator: ".")
        guard !keyMaterial.isEmpty, keyMaterial.count <= 2048 else {
            return false
        }
        return keyMaterial.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    /// Share links URL-encode the XHTTP `extra` JSON twice, so after the single
    /// round of query decoding performed by URLComponents the value still looks
    /// percent-encoded. Accept both the once- and the twice-encoded form, require
    /// a JSON object, canonicalize it, and cap its size; the core merges the
    /// object into `xhttpSettings` (top-level path/host/mode take priority).
    static func decodeXhttpExtra(_ value: String) -> String? {
        var candidates = [value]
        if let decoded = value.removingPercentEncoding {
            candidates.append(decoded)
        }
        for candidate in candidates {
            guard candidate.hasPrefix("{"), let data = candidate.data(using: .utf8) else {
                continue
            }
            guard let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                continue
            }
            guard let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
                continue
            }
            guard let text = String(data: normalized, encoding: .utf8), text.utf8.count <= 4096 else {
                continue
            }
            return text
        }
        return nil
    }

    static func isValidUUID(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5, [8, 4, 4, 4, 12] == parts.map({ $0.count }) else {
            return false
        }
        return value.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    static func isBase64URLString(_ value: String) -> Bool {
        let allowed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
        return !value.isEmpty && value.allSatisfy { allowed.contains($0) }
    }
}
