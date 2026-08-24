import CryptoKit
import Foundation

public enum WebProxyBridgeCapability {
    private static let contextPrefix = "tdesktop-web-proxy-bridge-v1\n"
    
    /// Derives the 43-character bridge query parameter from hostname + MTProxy secret bytes.
    public static func derive(hostname: String, secret: Data) -> String? {
        let normalizedHost = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard WebProxyHostname.isValid(normalizedHost) else {
            return nil
        }
        guard WebProxySecret.isSupported(secret) else {
            return nil
        }
        let context = Self.contextPrefix + normalizedHost
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(context.utf8), using: key)
        return Data(mac).webProxyBase64URLEncodedString()
    }
}

/// Which MTProxy secrets a WEB proxy accepts.
///
/// Telegram Desktop rejects `ee` TLS-emulation secrets for WEB, and so does this: the hosted relay
/// hands raw bytes to a stock MTProxy without adding the inner TLS-emulation record an `ee` secret
/// promises, so such a proxy would parse and save fine and then fail every handshake. Plain 16-byte
/// and `dd` random-padding secrets are the supported pair.
public enum WebProxySecret {
    public static func isSupported(_ secret: Data) -> Bool {
        if secret.count == 16 {
            return true
        }
        if secret.count == 17, secret.first == 0xdd {
            return true
        }
        return false
    }
}

public enum WebProxyHostname {
    /// WHATWG parses a host whose last label is a number as an IPv4 address, which is how `127.1`,
    /// `0x7f.1` and `1.2.3.4` all reach loopback or a bare address. A WEB proxy is always a real
    /// DNS name reached over HTTPS on 443, so those forms are rejected rather than left to differ
    /// between whatever resolves them.
    private static func isNumericLabel(_ label: Substring) -> Bool {
        if label.isEmpty {
            return false
        }
        if label.hasPrefix("0x") {
            let digits = label.dropFirst(2)
            return !digits.isEmpty && digits.allSatisfy({ $0.isHexDigit })
        }
        return label.allSatisfy({ $0.isASCII && $0.isNumber })
    }
    
    public static func isValid(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized.contains(":") || normalized.contains("/") {
            return false
        }
        if normalized.contains("@") || normalized.contains(" ") {
            return false
        }
        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            if label.isEmpty || label.count > 63 || label.hasPrefix("-") || label.hasSuffix("-") {
                return false
            }
            if label.unicodeScalars.contains(where: { !allowed.contains($0) }) {
                return false
            }
        }
        if let lastLabel = labels.last, isNumericLabel(lastLabel) {
            return false
        }
        return true
    }
}

extension Data {
    fileprivate func webProxyBase64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
