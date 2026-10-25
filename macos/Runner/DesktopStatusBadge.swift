import AppKit

/// Green connected mark on the Dock icon. Cleared when disconnected so no badge remains.
enum DesktopStatusBadge {
  private static var originalIcon: NSImage?
  private static var showingConnected = false

  static func setConnected(_ connected: Bool) {
    DispatchQueue.main.async {
      // Always clear the system (red) badge text — we never want "-ms" / leftover labels.
      NSApp.dockTile.badgeLabel = nil

      if connected {
        if showingConnected { return }
        if originalIcon == nil {
          originalIcon = NSApp.applicationIconImage
        }
        guard let base = originalIcon ?? NSApp.applicationIconImage else { return }
        NSApp.applicationIconImage = iconWithGreenMark(base)
        showingConnected = true
      } else {
        if let original = originalIcon {
          NSApp.applicationIconImage = original
        }
        showingConnected = false
      }
      NSApp.dockTile.display()
    }
  }

  private static func iconWithGreenMark(_ base: NSImage) -> NSImage {
    let size = base.size
    let out = NSImage(size: size)
    out.lockFocus()
    base.draw(
      in: NSRect(origin: .zero, size: size),
      from: .zero,
      operation: .sourceOver,
      fraction: 1
    )

    // Green status dot in the lower-right corner of the Dock icon.
    let diameter = min(size.width, size.height) * 0.28
    let margin = diameter * 0.25
    let rect = NSRect(
      x: size.width - diameter - margin,
      y: margin,
      width: diameter,
      height: diameter
    )
    let path = NSBezierPath(ovalIn: rect)
    NSColor.white.setFill()
    path.fill()

    let inset = diameter * 0.12
    let inner = rect.insetBy(dx: inset, dy: inset)
    let green = NSBezierPath(ovalIn: inner)
    NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1).setFill()
    green.fill()

    out.unlockFocus()
    out.isTemplate = false
    return out
  }
}
