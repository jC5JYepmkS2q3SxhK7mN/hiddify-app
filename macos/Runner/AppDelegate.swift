import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  // `Hiddify --tunnel <command>`, and `Hiddify tunnel <command>` as the service manager starts it, run
  // the core's command line from the bundled hiddify-core library instead of the app: builds without
  // a Developer ID run their VPN through it with administrator rights.
  static func main() {
    let arguments = CommandLine.arguments
    if arguments.count >= 2 && (arguments[1] == "--tunnel" || arguments[1] == "tunnel") {
      exit(runCoreCommand(["tunnel"] + arguments.dropFirst(2)))
    }
    exit(NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv))
  }

  private static func runCoreCommand(_ command: [String]) -> Int32 {
    guard let path = Bundle.main.privateFrameworksURL?.appendingPathComponent("hiddify-core.dylib").path,
          let library = dlopen(path, RTLD_NOW),
          let symbol = dlsym(library, "parseCli") else {
      fputs("hiddify-core is missing from the app bundle\n", stderr)
      return 1
    }
    typealias ParseCli = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<CChar>?
    let parseCli = unsafeBitCast(symbol, to: ParseCli.self)
    var argv = ([CommandLine.arguments[0]] + command).map { strdup($0) } + [nil]
    let error = argv.withUnsafeMutableBufferPointer { parseCli(Int32(command.count + 1), $0.baseAddress!) }
    argv.forEach { free($0) }
    guard let error = error else { return 0 }
    defer { free(error) }
    let message = String(cString: error)
    guard message.isEmpty else {
      fputs(message + "\n", stderr)
      return 1
    }
    return 0
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // https://github.com/leanflutter/window_manager/issues/214
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    super.applicationDidFinishLaunching(aNotification)
    // Request notification authorization
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, error in
      if let error = error {
        print("Error requesting notification authorization: \(error)")
      }
    }
  }
  // // window manager restore from dock: https://leanflutter.dev/blog/click-dock-icon-to-restore-after-closing-the-window
  // override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  //     if !flag {
  //         for window in NSApp.windows {
  //             if !window.isVisible {
  //                 window.setIsVisible(true)
  //             }
  //             window.makeKeyAndOrderFront(self)
  //             NSApp.activate(ignoringOtherApps: true)
  //         }
  //     }
  //     return true
  // }
}
