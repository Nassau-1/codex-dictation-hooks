import AppKit

final class HookHudView: NSView {
    private var phase = 0
    private var timer: Timer?
    private let message: String?

    init(frame frameRect: NSRect, message: String? = nil) {
        self.message = message
        super.init(frame: frameRect)
        wantsLayer = true
        if message == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.phase = (self.phase + 1) % 4
                self.needsDisplay = true
            }
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

        let pillRect = bounds.insetBy(dx: 5, dy: 5)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)

        NSColor(calibratedWhite: 0.05, alpha: 0.78).setFill()
        pillPath.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
        pillPath.lineWidth = 1
        pillPath.stroke()

        if let message {
            drawNotice(message, in: pillRect)
            return
        }

        let dotDiameter: CGFloat = 6
        let dotGap: CGFloat = 5
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

    private func drawNotice(_ message: String, in rect: NSRect) {
        let dotDiameter: CGFloat = 7
        let dotRect = NSRect(x: rect.minX + 14, y: rect.midY - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
        NSColor.systemOrange.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.88)
        ]
        let textRect = NSRect(x: dotRect.maxX + 9, y: rect.midY - 8, width: rect.width - 42, height: 18)
        NSString(string: message).draw(in: textRect, withAttributes: attributes)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let isNotice = CommandLine.arguments.dropFirst().first == "error"
let noticeMessage = isNotice
    ? CommandLine.arguments.dropFirst(2).joined(separator: " ")
    : nil
let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
let height: CGFloat = isNotice ? 40 : 32
let width: CGFloat = {
    guard let noticeMessage else { return 76 }
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
    let measured = NSString(string: noticeMessage).size(withAttributes: attributes).width + 56
    return min(max(measured, 168), 340)
}()
let edgeInset: CGFloat = 22
let origin = NSPoint(
    x: frame.maxX - width - edgeInset,
    y: frame.minY + edgeInset
)

let window = NSPanel(
    contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)

window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.level = .floating
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
window.contentView = HookHudView(frame: NSRect(x: 0, y: 0, width: width, height: height), message: noticeMessage)
window.orderFrontRegardless()

if isNotice {
    Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { _ in
        NSApplication.shared.terminate(nil)
    }
}

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
