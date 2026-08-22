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
        guard !secret.isEmpty else {
            return nil
        }
        let context = Self.contextPrefix + normalizedHost
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(context.utf8), using: key)
        return Data(mac).webProxyBase64URLEncodedString()
    }
}

public enum WebProxyHostname {
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
