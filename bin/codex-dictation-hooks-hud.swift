import AppKit

final class HookHudView: NSView {
    private var phase = 0
    private var timer: Timer?
    private let message: String?
    private let noticeKind: String

    init(frame frameRect: NSRect, message: String? = nil, noticeKind: String = "info") {
        self.message = message
        self.noticeKind = noticeKind
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
            if noticeKind == "tally" {
                drawTallyNotice(message, in: pillRect)
            } else {
                drawNotice(message, in: pillRect)
            }
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
        let dotColor = noticeKind == "error"
            ? NSColor.systemOrange.withAlphaComponent(0.9)
            : NSColor.controlAccentColor.withAlphaComponent(0.85)
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.88)
        ]
        let textRect = NSRect(x: dotRect.maxX + 9, y: rect.midY - 8, width: rect.width - 42, height: 18)
        NSString(string: message).draw(in: textRect, withAttributes: attributes)
    }

    private func drawTallyNotice(_ message: String, in rect: NSRect) {
        let parts = message.components(separatedBy: "||")
        let added = parts.first ?? message
        let total = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)

        let dotDiameter: CGFloat = 7
        let dotRect = NSRect(x: rect.minX + 14, y: rect.midY - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
        NSColor.systemGreen.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let primaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.9)
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.62)
        ]

        var x = dotRect.maxX + 9
        let y = rect.midY - 8
        NSString(string: added).draw(at: NSPoint(x: x, y: y), withAttributes: primaryAttributes)
        x += NSString(string: added).size(withAttributes: primaryAttributes).width + 8

        if !total.isEmpty {
            NSString(string: "•").draw(at: NSPoint(x: x, y: y), withAttributes: secondaryAttributes)
            x += NSString(string: "•").size(withAttributes: secondaryAttributes).width + 8
            NSString(string: total).draw(at: NSPoint(x: x, y: y), withAttributes: secondaryAttributes)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let noticeArgs = Array(CommandLine.arguments.dropFirst())
let noticeKind = noticeArgs.first ?? ""
let hasExplicitDuration = noticeArgs.count > 2 && TimeInterval(noticeArgs[1]) != nil
let durationSeconds: TimeInterval = {
    guard hasExplicitDuration, let duration = TimeInterval(noticeArgs[1]) else { return 5.0 }
    return max(0.8, min(duration, 20.0))
}()
let isNotice = noticeKind == "error" || noticeKind == "info" || noticeKind == "tally"
let noticeMessage = isNotice
    ? noticeArgs.dropFirst(hasExplicitDuration ? 2 : 1).joined(separator: " ")
    : nil
let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
let height: CGFloat = isNotice ? 40 : 32
let width: CGFloat = {
    guard let noticeMessage else { return 76 }
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
    let measuredText = noticeKind == "tally"
        ? noticeMessage.replacingOccurrences(of: "||", with: "  •  ")
        : noticeMessage
    let measured = NSString(string: measuredText).size(withAttributes: attributes).width + 62
    return min(max(measured, 168), noticeKind == "tally" ? 420 : 340)
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
window.contentView = HookHudView(frame: NSRect(x: 0, y: 0, width: width, height: height), message: noticeMessage, noticeKind: noticeKind)
window.orderFrontRegardless()

if isNotice {
    Timer.scheduledTimer(withTimeInterval: durationSeconds, repeats: false) { _ in
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
