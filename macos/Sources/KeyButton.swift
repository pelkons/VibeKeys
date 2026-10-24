// A rounded, flat button that never takes keyboard focus, so clicks leave the user's text field focused.

import AppKit

enum Palette {
    static let background = NSColor(srgbRed: 45 / 255, green: 45 / 255, blue: 48 / 255, alpha: 0.92)
    static let button = NSColor(white: 1, alpha: 0.10)
    static let hover = NSColor(srgbRed: 0, green: 122 / 255, blue: 204 / 255, alpha: 1)
    static let recording = NSColor(srgbRed: 32 / 255, green: 92 / 255, blue: 150 / 255, alpha: 1)
    static let grip = NSColor(white: 1, alpha: 0.35)
}

final class KeyButton: NSView {
    /// Called on a normal click (press and release inside the button)
    var onPress: (() -> Void)?
    /// When set, called on mouse down instead and the owner does its own tracking (long press)
    var onMouseDown: ((NSEvent) -> Void)?

    var fill = Palette.button { didSet { needsDisplay = true } }
    var hoverFill = Palette.hover { didSet { needsDisplay = true } }
    /// Drawn as hovered regardless of the mouse (popup slide tracking)
    var highlighted = false { didSet { needsDisplay = true } }
    var pressed = false { didSet { needsDisplay = true } }

    let text: String?
    private let image: NSImage?
    private let scale: CGFloat
    private let textSize: CGFloat
    private var hovering = false

    init(symbol: String?, text: String?, tooltip: String, frame: NSRect, scale: CGFloat, textSize: CGFloat = 13) {
        self.text = text
        self.scale = scale
        self.textSize = textSize
        if let symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 15 * scale, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        } else {
            image = nil
        }
        super.init(frame: frame)
        toolTip = tooltip.isEmpty ? nil : tooltip
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        if let onMouseDown { onMouseDown(event); return }
        pressed = true
        var inside = true
        // Track until release, like a regular button: fire only if released inside
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            pressed = inside
            if next.type == .leftMouseUp { break }
        }
        pressed = false
        if inside { onPress?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        var color = hovering || highlighted ? hoverFill : fill
        if pressed { color = color.blended(withFraction: 0.2, of: .black) ?? color }
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6 * scale, yRadius: 6 * scale).fill()

        if let image {
            let size = image.size
            image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                  width: size.width, height: size.height))
        } else if let text {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: textSize * scale, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
    }
}

/// The dotted handle at the left: drag to move the panel, right-click (or Control-click) for the menu.
final class GripView: NSView {
    var onDragEnd: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    private let scale: CGFloat

    init(frame: NSRect, scale: CGFloat) {
        self.scale = scale
        super.init(frame: frame)
        toolTip = "Тянуть — переместить, правый клик — меню"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(event); return }
        guard let window else { return }
        let start = NSEvent.mouseLocation
        let origin = window.frame.origin
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
            if next.type == .leftMouseUp { break }
        }
        onDragEnd?()
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    private func showMenu(_ event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.grip.setFill()
        let dot = 3 * scale, step = 6 * scale
        let left = (bounds.width - dot - step) / 2, bottom = (bounds.height - dot - 2 * step) / 2
        for column in 0..<2 {
            for row in 0..<3 {
                NSBezierPath(ovalIn: NSRect(x: left + CGFloat(column) * step, y: bottom + CGFloat(row) * step,
                                            width: dot, height: dot)).fill()
            }
        }
    }
}
