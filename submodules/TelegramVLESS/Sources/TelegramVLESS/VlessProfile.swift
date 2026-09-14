import Foundation

/// A parsed and validated `vless://` share-link profile.
///
/// The parameter space mirrors the strict allowlist of the reference desktop
/// integration (telegramvless `Core::ParseVlessProfile`): anything outside the
/// supported subset is rejected instead of silently ignored, so a profile that
/// parses here is guaranteed to be fully expressible in the generated Xray
/// configuration.
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
        grpcMultiMode: Bool = false
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
}

private let allowedParameters: Set<String> = [
    "encryption", "flow", "security", "sni", "fp", "alpn", "pbk", "sid", "spx",
    "type", "host", "path", "serviceName", "mode", "authority",
]

public enum VlessProfileParser {
    public static let maximumUriLength = 4096

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

        // encryption: VLESS supports only "none".
        let encryption = (query["encryption"] ?? "none").lowercased()
        guard encryption == "none" else {
            return .failure(.unsupportedEncryption(encryption))
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
        switch transport {
        case .tcp:
            for key in ["path", "host", "serviceName", "mode", "authority"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
        case .ws, .httpupgrade:
            if let rawPath = query["path"], !rawPath.isEmpty {
                path = rawPath
            }
            if let rawHost = query["host"], !rawHost.isEmpty {
                transportHost = rawHost
            }
            for key in ["serviceName", "mode", "authority"] where (query[key] ?? "").isEmpty == false {
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
            for key in ["path", "host"] where (query[key] ?? "").isEmpty == false {
                return .failure(.unsupportedParameter(key))
            }
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
            grpcMultiMode: grpcMultiMode
        ))
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
