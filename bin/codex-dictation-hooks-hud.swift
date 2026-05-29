import AppKit

final class HookHudView: NSView {
    private var phase = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase = (self.phase + 1) % 4
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        timer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillRect = bounds.insetBy(dx: 12, dy: 10)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)

        NSColor(calibratedWhite: 0.05, alpha: 0.86).setFill()
        pillPath.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.11).setStroke()
        pillPath.lineWidth = 1.2
        pillPath.stroke()

        let dotDiameter: CGFloat = 12
        let dotGap: CGFloat = 7
        let totalWidth = dotDiameter * 4 + dotGap * 3
        let startX = bounds.midX - totalWidth / 2
        let y = bounds.midY - dotDiameter / 2

        for index in 0..<4 {
            let distance = (index - phase + 4) % 4
            let alpha = [1.0, 0.72, 0.48, 0.72][distance]
            NSColor(calibratedWhite: 1.0, alpha: alpha).setFill()

            let x = startX + CGFloat(index) * (dotDiameter + dotGap)
            let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter))
            dot.fill()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
let width: CGFloat = 132
let height: CGFloat = 64
let origin = NSPoint(
    x: frame.midX - width / 2,
    y: frame.midY - height / 2
)

let window = NSPanel(
    contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)

window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = true
window.level = .floating
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
window.contentView = HookHudView(frame: NSRect(x: 0, y: 0, width: width, height: height))
window.orderFrontRegardless()

signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

signal(SIGINT) { _ in
    DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
    }
}

app.run()
