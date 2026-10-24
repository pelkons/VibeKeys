// A column of extra characters that pops up above a panel button on long press, like the
// alternate-key popup on a phone keyboard. Pick a character by clicking it, or by sliding onto it
// while still holding the mouse button.

import AppKit

final class SymbolPopup {
    var onClose: (() -> Void)?
    /// Stays open even when the mouse is away (demo screenshot)
    var keepOpen = false

    private let panel: KeyPanel
    private var buttons: [KeyButton] = []
    private var anchorRect: NSRect
    private var watch: Timer?
    private var lastNear = Date()
    private static let closeAfter: TimeInterval = 1.5   // closes once the mouse has been away this long

    /// symbols: the first one sits right above the anchor button, the rest stack upward
    init(above anchor: KeyButton, symbols: String, scale: CGFloat) {
        let gap = max(1, 2 * scale)
        let size = anchor.frame.size
        let content = NSSize(width: size.width + 4 * gap,
                             height: CGFloat(symbols.count) * (size.height + 2 * gap) + 2 * gap)
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: content))
        anchorRect = anchor.window?.convertToScreen(anchor.convert(anchor.bounds, to: nil)) ?? .zero

        let background = KeyPanel.background(size: content, scale: scale)
        for (index, character) in symbols.enumerated() {
            let frame = NSRect(x: 2 * gap, y: 2 * gap + CGFloat(index) * (size.height + 2 * gap),
                               width: size.width, height: size.height)
            let button = KeyButton(symbol: nil, text: String(character), tooltip: "", frame: frame, scale: scale, textSize: 16)
            button.onPress = { [weak self, unowned button] in self?.pick(button) }
            background.addSubview(button)
            buttons.append(button)
        }
        panel.contentView = background

        var origin = NSPoint(x: anchorRect.minX - 2 * gap, y: anchorRect.maxY + 3 * gap)
        if let screen = anchor.window?.screen, origin.y + content.height > screen.frame.maxY {
            origin.y = anchorRect.minY - 3 * gap - content.height   // no room above: open downward
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        watch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.checkMouse() }
    }

    /// Lights up the symbol under a screen point (used while the long-pressed button is still held)
    func highlight(at point: NSPoint) {
        for button in buttons { button.highlighted = screenFrame(of: button).contains(point) }
    }

    func highlightIndex(_ index: Int) {
        for (i, button) in buttons.enumerated() { button.highlighted = i == index }
    }

    /// Mouse released after a long press: type the symbol under it, otherwise stay open for a click
    func releaseAt(_ point: NSPoint) {
        if let button = buttons.first(where: { screenFrame(of: $0).contains(point) }) {
            pick(button)
        } else {
            highlight(at: .zero)
        }
    }

    func close() {
        watch?.invalidate()
        watch = nil
        panel.orderOut(nil)
        onClose?()
    }

    private func pick(_ button: KeyButton) {
        if let text = button.text { Keyboard.type(text) }
        close()
    }

    private func checkMouse() {
        let mouse = NSEvent.mouseLocation
        if keepOpen || panel.frame.contains(mouse) || anchorRect.contains(mouse) {
            lastNear = Date()
        } else if Date().timeIntervalSince(lastNear) > Self.closeAfter {
            close()
        }
    }

    private func screenFrame(of view: NSView) -> NSRect {
        view.window?.convertToScreen(view.convert(view.bounds, to: nil)) ?? .zero
    }
}
