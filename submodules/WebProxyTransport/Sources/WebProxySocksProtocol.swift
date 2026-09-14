import Foundation

/// Address of a stream target, as carried in an `OPEN` frame payload when the relay has
/// advertised arbitrary stream targets (WELCOME capability bit 0 — see
/// `docs/webproxy-socks-bridge.md` for the relay-side contract). Wire format:
///
///     [atyp: 0x01 IPv4 | 0x03 domain | 0x04 IPv6] [address bytes] [port: 2 bytes, big endian]
///
/// An `OPEN` with an empty payload keeps its legacy meaning — the relay's own backing MTProxy —
/// so relays that never set the capability bit are unaffected.
public enum WebProxyStreamTarget: Equatable {
    case ipv4(Data)
    case ipv6(Data)
    case domain(String)

    public static let atypIPv4: UInt8 = 0x01
    public static let atypDomain: UInt8 = 0x03
    public static let atypIPv6: UInt8 = 0x04

    public func openPayload(port: UInt16) -> Data {
        var data = Data()
        switch self {
        case let .ipv4(bytes):
            data.append(Self.atypIPv4)
            data.append(bytes)
        case let .ipv6(bytes):
            data.append(Self.atypIPv6)
            data.append(bytes)
        case let .domain(name):
            data.append(Self.atypDomain)
            data.append(UInt8(clamping: name.utf8.count))
            data.append(contentsOf: name.utf8)
        }
        data.append(contentsOf: [UInt8((port >> 8) & 0xff), UInt8(port & 0xff)])
        return data
    }
}

/// Pure SOCKS5 (RFC 1928) message codec, including the RFC 1929 username/password
/// sub-negotiation, for the sidecar's local SOCKS5 listener. Stateless functions over byte
/// buffers so the framing is unit-testable the same way `WebSocketFrame` is; the sidecar owns
/// the state machine.
///
/// The listener deliberately requires username/password auth (method `0x02`) with a
/// per-sidecar-start random credential: a loopback SOCKS5 endpoint that dials arbitrary targets
/// through the user's relay is exactly the thing a same-device process should not be able to use
/// for free, and iOS does not isolate loopback ports between apps.
public enum Socks5Protocol {
    public static let version: UInt8 = 0x05
    public static let methodNoAuthentication: UInt8 = 0x00
    public static let methodUsernamePassword: UInt8 = 0x02
    public static let methodNoAcceptable: UInt8 = 0xff

    public enum Outcome<T> {
        /// A complete message was parsed; `consumed` bytes must be removed from the buffer.
        case parsed(value: T, consumed: Int)
        /// The buffer holds a prefix of a valid message; read more.
        case needMoreData
        /// The buffer cannot be a valid message; the connection should be dropped.
        case invalid
    }

    // MARK: Method selection (RFC 1928 §3)

    /// `[VER, NMETHODS, METHODS...]` — the offered method list.
    public static func parseMethodSelection(_ buffer: Data) -> Outcome<[UInt8]> {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else {
            return .needMoreData
        }
        guard bytes[0] == version, bytes[1] >= 1 else {
            return .invalid
        }
        let methodCount = Int(bytes[1])
        guard bytes.count >= 2 + methodCount else {
            return .needMoreData
        }
        return .parsed(value: Array(bytes[2 ..< (2 + methodCount)]), consumed: 2 + methodCount)
    }

    public static func methodSelectionReply(method: UInt8) -> Data {
        return Data([version, method])
    }

    // MARK: Username/password sub-negotiation (RFC 1929)

    /// `[0x01, ULEN, UNAME, PLEN, PASSWD]`.
    public static func parseUsernamePasswordRequest(_ buffer: Data) -> Outcome<(username: String, password: String)> {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else {
            return .needMoreData
        }
        guard bytes[0] == 0x01 else {
            return .invalid
        }
        let usernameLength = Int(bytes[1])
        guard bytes.count >= 2 + usernameLength else {
            return .needMoreData
        }
        guard let username = String(bytes: bytes[2 ..< (2 + usernameLength)], encoding: .utf8) else {
            return .invalid
        }
        let passwordOffset = 2 + usernameLength
        guard bytes.count >= passwordOffset + 1 else {
            return .needMoreData
        }
        let passwordLength = Int(bytes[passwordOffset])
        guard bytes.count >= passwordOffset + 1 + passwordLength else {
            return .needMoreData
        }
        guard let password = String(bytes: bytes[(passwordOffset + 1) ..< (passwordOffset + 1 + passwordLength)], encoding: .utf8) else {
            return .invalid
        }
        return .parsed(value: (username, password), consumed: 2 + usernameLength + 1 + passwordLength)
    }

    public static func usernamePasswordReply(succeeded: Bool) -> Data {
        return Data([0x01, succeeded ? 0x00 : 0x01])
    }

    // MARK: CONNECT request (RFC 1928 §4)

    /// `[VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT]` with CMD == 0x01 (CONNECT) only.
    public static func parseConnectRequest(_ buffer: Data) -> Outcome<(target: WebProxyStreamTarget, port: UInt16)> {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 4 else {
            return .needMoreData
        }
        guard bytes[0] == version, bytes[1] == 0x01, bytes[2] == 0x00 else {
            return .invalid
        }
        let addressOffset = 4
        switch bytes[3] {
        case WebProxyStreamTarget.atypIPv4:
            guard bytes.count >= addressOffset + 4 + 2 else {
                return .needMoreData
            }
            let address = Data(bytes[addressOffset ..< (addressOffset + 4)])
            let port = UInt16(bytes[addressOffset + 4]) << 8 | UInt16(bytes[addressOffset + 5])
            return .parsed(value: (.ipv4(address), port), consumed: addressOffset + 4 + 2)
        case WebProxyStreamTarget.atypDomain:
            guard bytes.count >= addressOffset + 1 else {
                return .needMoreData
            }
            let nameLength = Int(bytes[addressOffset])
            guard bytes.count >= addressOffset + 1 + nameLength + 2 else {
                return .needMoreData
            }
            guard let name = String(bytes: bytes[(addressOffset + 1) ..< (addressOffset + 1 + nameLength)], encoding: .utf8), !name.isEmpty else {
                return .invalid
            }
            let portOffset = addressOffset + 1 + nameLength
            let port = UInt16(bytes[portOffset]) << 8 | UInt16(bytes[portOffset + 1])
            return .parsed(value: (.domain(name), port), consumed: portOffset + 2)
        case WebProxyStreamTarget.atypIPv6:
            guard bytes.count >= addressOffset + 16 + 2 else {
                return .needMoreData
            }
            let address = Data(bytes[addressOffset ..< (addressOffset + 16)])
            let port = UInt16(bytes[addressOffset + 16]) << 8 | UInt16(bytes[addressOffset + 17])
            return .parsed(value: (.ipv6(address), port), consumed: addressOffset + 16 + 2)
        default:
            return .invalid
        }
    }

    /// BND.ADDR 0.0.0.0 / BND.PORT 0 — clients ignore them, and advertising the real loopback
    /// endpoint would tell a same-device caller nothing it does not already know.
    public static func connectReply(succeeded: Bool) -> Data {
        return Data([
            version,
            succeeded ? 0x00 : 0x01,
            0x00,
            WebProxyStreamTarget.atypIPv4,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00
        ])
    }
}
