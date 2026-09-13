import Foundation

/// A minimal, typed client for the libxray structured invoke API
/// (XTLS/libxray, `Invoke`/`CGoInvoke`, apiVersion 3).
///
/// When the `LibXray` module is not linked (the prebuilt xcframework has not
/// been added to this target), `isAvailable` is false and every method fails
/// with `.runtimeUnavailable` - the rest of the package stays compilable and
/// testable without the binary.
public protocol XrayRuntime {
    var isAvailable: Bool { get }

    /// Allocates `count` free local TCP ports.
    func getFreePorts(count: Int) throws -> [Int]
    /// Starts Xray in-process with a complete JSON configuration.
    func start(configJSON: String) throws
    func stop() throws
    func isRunning() -> Bool
    func version() -> String?
}

public enum XrayRuntimeError: Error, Equatable {
    case runtimeUnavailable
    case invokeFailed(String)
    case responseDecodeFailed
    case portAllocationFailed
}

#if canImport(LibXray)
import LibXray
#endif

public final class LibXrayRuntime: XrayRuntime {
    private static let apiVersion = 3

    public init() {}

    public var isAvailable: Bool {
        #if canImport(LibXray)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Invoke plumbing

    private struct InvokeResponse: Decodable {
        var success: Bool?
        var data: Data?
        var error: String?
    }

    private struct Payload: Decodable {
        var ports: [Int]?
        var running: Bool?
        var version: String?
    }

    private func invoke(_ method: String, payload: [String: Any]?) throws -> Payload? {
        #if canImport(LibXray)
        var request: [String: Any] = [
            "apiVersion": Self.apiVersion,
            "method": method,
        ]
        if let payload = payload {
            request["payload"] = payload
        }
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw XrayRuntimeError.responseDecodeFailed
        }

        let responseCString: UnsafeMutablePointer<CChar>? = requestJSON.utf8CString.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<CChar>? in
            guard let base = buffer.baseAddress else {
                return nil
            }
            return CGoInvoke(UnsafeMutablePointer(mutating: base))
        }
        guard let responseCString = responseCString else {
            throw XrayRuntimeError.invokeFailed("CGoInvoke returned nil")
        }
        defer { CGoFree(responseCString) }

        let responseString = String(cString: responseCString)
        guard let responseData = responseString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(InvokeResponse.self, from: responseData) else {
            throw XrayRuntimeError.responseDecodeFailed
        }
        guard decoded.success == true, decoded.error == nil else {
            throw XrayRuntimeError.invokeFailed(decoded.error ?? "unknown failure")
        }
        guard let data = decoded.data else {
            return nil
        }
        return try? JSONDecoder().decode(Payload.self, from: data)
        #else
        _ = method
        _ = payload
        throw XrayRuntimeError.runtimeUnavailable
        #endif
    }

    // MARK: - XrayRuntime

    public func getFreePorts(count: Int) throws -> [Int] {
        let response = try invoke("getFreePorts", payload: ["count": count])
        guard let ports = response?.ports, ports.count == count, ports.allSatisfy({ $0 > 0 && $0 <= 65535 }) else {
            throw XrayRuntimeError.portAllocationFailed
        }
        return ports
    }

    public func start(configJSON: String) throws {
        _ = try invoke("runXray", payload: ["xrayJson": configJSON])
    }

    public func stop() throws {
        _ = try invoke("stopXray", payload: [:])
    }

    public func isRunning() -> Bool {
        let response = try? invoke("getXrayState", payload: [:])
        return response?.running ?? false
    }

    public func version() -> String? {
        let response = try? invoke("xrayVersion", payload: [:])
        return response?.version
    }
}
