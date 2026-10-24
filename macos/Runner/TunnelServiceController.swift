import FlutterMacOS
import Foundation

// Builds without a Developer ID cannot use a Network Extension. Their VPN runs the full core in
// hiddify-core's tunnel service: the app's own executable, run as `Hiddify --tunnel run` by launchd
// with administrator rights. This controller mirrors MacOSVPNController's method-channel contract
// (initialize/start/stop returning available, port, secret, status) so Dart can reuse the useTunnel path.
final class TunnelServiceController {
    private static let servicePort: UInt16 = 18020
    private static let secretPath =
        "/Library/Application Support/Hiddify/TunnelService/data/control.secret"
    private static let buildStampPath =
        "/Library/Application Support/Hiddify/TunnelService/data/build.id"
    private let queue = DispatchQueue(label: "app.hiddify.tunnel-service")
    private var connected = false
    private var lastMessage: String?

    private var installScript: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("TunnelService/install-tunnel-service.sh")
    }

    var available: Bool {
        guard let script = installScript else { return false }
        return FileManager.default.fileExists(atPath: script.path)
    }

    func state() -> [String: Any] {
        var result: [String: Any] = [
            "available": available,
            "tunnelService": available,
            "status": connected ? "connected" : "disconnected",
            "activation": "idle",
            "port": Int(Self.servicePort),
        ]
        if let secret = try? Self.readSecret() { result["secret"] = secret }
        if let message = lastMessage { result["message"] = message }
        return result
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
        case "initialize", "status":
            result(state())
        case "start":
            guard available else {
                result(Self.flutterError("The VPN service is missing from this build. Proxy modes are available."))
                return
            }
            guard let arguments = call.arguments as? [String: Any] else {
                result(Self.flutterError("Missing VPN configuration."))
                return
            }
            queue.async {
                let error = self.start(arguments: arguments)
                DispatchQueue.main.async {
                    if let error = error {
                        self.connected = false
                        self.lastMessage = error
                        result(Self.flutterError(error))
                    } else {
                        self.connected = true
                        self.lastMessage = nil
                        result(self.state())
                    }
                }
            }
        case "stop", "reset":
            queue.async {
                let error = self.stopTunnel()
                DispatchQueue.main.async {
                    self.connected = false
                    self.lastMessage = error
                    if call.method == "reset", let error = error {
                        result(Self.flutterError(error))
                    } else {
                        result(self.state())
                    }
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func start(arguments: [String: Any]) -> String? {
        if let error = ensureInstalledSync() { return error }
        guard let configContent = arguments["configContent"] as? String, !configContent.isEmpty,
              let settingsJSON = arguments["settingsJSON"] as? String else {
            return "The VPN configuration is incomplete."
        }
        var resources: [String: String] = [:]
        for (name, value) in arguments["resources"] as? [String: FlutterStandardTypedData] ?? [:] {
            resources[name] = value.data.base64EncodedString()
        }
        let request: [String: Any] = [
            "configContent": configContent,
            "configName": arguments["configName"] as? String ?? "Hiddify",
            "settingsJSON": settingsJSON,
            "resources": resources,
            "disableMemoryLimit": arguments["disableMemoryLimit"] as? Bool ?? false,
            "ownerPid": ProcessInfo.processInfo.processIdentifier,
        ]
        let requestURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiddify-tunnel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: requestURL) }
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            try data.write(to: requestURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        } catch {
            return "Couldn't prepare the VPN configuration."
        }
        if let error = runTunnelCommand(["connect", requestURL.path]) { return error }
        return nil
    }

    private func stopTunnel() -> String? {
        runTunnelCommand(["disconnect"])
    }

    private func runTunnelCommand(_ arguments: [String]) -> String? {
        guard let executable = Bundle.main.executableURL?.path else {
            return "The app executable is missing."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--tunnel"] + arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Couldn't talk to the VPN service."
        }
        if process.terminationStatus == 0 { return nil }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : "The VPN service command failed."
    }

    private func ensureInstalled(_ completion: @escaping (String?) -> Void) {
        queue.async {
            let error = self.ensureInstalledSync()
            DispatchQueue.main.async { completion(error) }
        }
    }

    private func ensureInstalledSync() -> String? {
        // The build id lives only in hiddify-core (Go). Ask this app's core for it and compare
        // to the running service stamp — Dart never embeds the value.
        if serviceReady() { return nil }
        if let error = install() { return error }
        for _ in 0..<50 where !serviceReady() {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if !serviceReady() {
            if (try? Self.readSecret()) == nil {
                return "The VPN service secret is missing. Reinstall the VPN service."
            }
            if !Self.serviceListening() {
                return "The VPN service was installed but did not start."
            }
            return "The VPN service is still running a different Hiddify core. Try connecting again."
        }
        return nil
    }

    private func serviceReady() -> Bool {
        guard (try? Self.readSecret()) != nil, Self.serviceListening(),
              let bundled = bundledCoreBuildId(),
              let stamped = try? Self.readBuildStamp() else { return false }
        return bundled == stamped
    }

    // Prints the build id embedded in this app's hiddify-core (via Hiddify --tunnel build-id).
    private func bundledCoreBuildId() -> String? {
        guard let executable = Bundle.main.executableURL?.path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--tunnel", "build-id"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let id = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, id != "unset" else { return nil }
        return id
    }

    private static func readSecret() throws -> String {
        let secret = try String(contentsOfFile: secretPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard secret.count >= 32 else { throw CocoaError(.fileReadCorruptFile) }
        return secret
    }

    private static func readBuildStamp() throws -> String {
        try String(contentsOfFile: buildStampPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func install() -> String? {
        guard let script = installScript?.path else { return "The VPN service is missing from this build." }
        let quote = { (text: String) in
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let owner = NSUserName()
        let source = "do shell script \"/bin/bash \" & quoted form of \(quote(script)) & \" \" & quoted form of "
            + "\(quote(Bundle.main.bundlePath)) & \" \" & quoted form of \(quote(owner)) with prompt "
            + "\"VPN mode sends all of this Mac's traffic through Hiddify, "
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
