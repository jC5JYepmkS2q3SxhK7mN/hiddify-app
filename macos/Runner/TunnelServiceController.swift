import CryptoKit
import FlutterMacOS
import Foundation

// Builds without a Developer ID cannot use a Network Extension. Their VPN runs in hiddify-core's
// tunnel service instead: the app's own executable, run as `Hiddify --tunnel run` by launchd with
// administrator rights, which takes the traffic into a TUN and hands it to the core in the app. Dart
// drives the service over gRPC; this only installs it, once, with an administrator password.
final class TunnelServiceController {
    private static let installedApp = "/Library/Application Support/Hiddify/TunnelService/Hiddify.app"
    private static let servicePort: UInt16 = 18020
    private let queue = DispatchQueue(label: "app.hiddify.tunnel-service")

    private var coreLibrary: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("hiddify-core.dylib")
    }

    private var installScript: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("TunnelService/install-tunnel-service.sh")
    }

    var available: Bool {
        guard let script = installScript else { return false }
        return FileManager.default.fileExists(atPath: script.path)
    }

    func state() -> [String: Any] {
        ["available": false, "tunnelService": available, "status": "disconnected", "activation": "idle"]
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "installTunnelService":
            guard available else {
                result(Self.flutterError("The VPN service is missing from this build. Proxy modes are available."))
                return
            }
            ensureInstalled { error in
                if let error = error { result(Self.flutterError(error)) } else { result(nil) }
            }
        case "initialize", "status", "stop", "reset":
            result(state())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func ensureInstalled(_ completion: @escaping (String?) -> Void) {
        queue.async {
            let current = self.installedServiceIsCurrent()
            DispatchQueue.main.async {
                if current { completion(nil); return }
                if let error = self.install() { completion(error); return }
                self.queue.async {
                    // launchd starts the service right away; wait for it to listen.
                    for _ in 0..<50 where !Self.serviceListening() {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    let ready = Self.serviceListening()
                    DispatchQueue.main.async {
                        completion(ready ? nil : "The VPN service was installed but did not start.")
                    }
                }
            }
        }
    }

    // The service is current when it answers and runs this app's core library.
    private func installedServiceIsCurrent() -> Bool {
        guard let library = coreLibrary, Self.serviceListening(),
              let installedHash = Self.sha256(URL(fileURLWithPath: Self.installedApp)
                  .appendingPathComponent("Contents/Frameworks/hiddify-core.dylib")),
              let bundledHash = Self.sha256(library) else { return false }
        return installedHash == bundledHash
    }

    private static func sha256(_ url: URL) -> SHA256.Digest? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return SHA256.hash(data: data)
    }

    private static func serviceListening() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = servicePort.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    // Runs the bundled install script as root after macOS asks for an administrator password.
    private func install() -> String? {
        guard let script = installScript?.path else { return "The VPN service is missing from this build." }
        let quote = { (text: String) in
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "do shell script \"/bin/bash \" & quoted form of \(quote(script)) & \" \" & quoted form of "
            + "\(quote(Bundle.main.bundlePath)) with prompt \"VPN mode sends all of this Mac's traffic through Hiddify, "
            + "which needs administrator permission. Hiddify asks for it once.\" "
            + "with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error = error else { return nil }
        if error[NSAppleScript.errorNumber] as? Int == -128 {
            return "Installing the VPN service was cancelled."
        }
        return "Couldn't install the VPN service: \(error[NSAppleScript.errorMessage] as? String ?? "unknown error")"
    }

    private static func flutterError(_ message: String) -> FlutterError {
        FlutterError(code: "MACOS_VPN", message: message, details: nil)
    }
}
