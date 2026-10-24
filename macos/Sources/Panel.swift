// The floating key panel: a non-activating panel that stays above all windows (and the Dock)
// on every Space, never takes focus, and sends its keys to the app you are typing in.

import AppKit
import Carbon.HIToolbox

/// Borderless panel that never becomes key or main, so the frontmost app keeps keyboard focus.
final class KeyPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar   // above normal windows and the Dock
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Rounded dark background used by the panel and the symbol popup
    static func background(size: NSSize, scale: CGFloat) -> NSView {
        let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 10 * scale
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        return view
    }
}

final class PanelController {
    enum Kind { case plain, dictation, backspace }

    struct Key {
        let symbol: String?
        let text: String?
        let tip: String
        let keys: [Int]
        let kind: Kind
        init(symbol: String? = nil, text: String? = nil, _ tip: String, _ keys: [Int], _ kind: Kind = .plain) {
            self.symbol = symbol; self.text = text; self.tip = tip; self.keys = keys; self.kind = kind
        }
    }

    // ---- Buttons, left to right. On a Mac, Command takes the place of Windows' Ctrl. ----
    static let keys: [Key] = [
        Key(symbol: "mic", "Диктовка OpenWhispr", [], .dictation),
        Key(symbol: "checkmark", "Подтвердить (Cmd+Enter)", [kVK_Command, kVK_Return]),
        Key(symbol: "return", "Enter", [kVK_Return]),
        Key(symbol: "text.alignleft", "Новая строка (Shift+Enter)", [kVK_Shift, kVK_Return]),
        Key(symbol: "arrow.uturn.backward", "Отменить (Cmd+Z)", [kVK_Command, kVK_ANSI_Z]),
        Key(text: "esc", "Escape", [kVK_Escape]),
        Key(symbol: "camera.viewfinder", "Скриншот области (Cmd+Shift+4)", [kVK_Command, kVK_Shift, kVK_ANSI_4]),
        Key(symbol: "delete.left", "Стереть (Backspace); подержать — знаки", [kVK_Delete], .backspace),
    ]

    /// Long press on Backspace pops up these characters, first one closest to the button
    static let backspaceSymbols = ".?,!"
    static let longPress: TimeInterval = 0.45
    static let silenceMs = 2000, noSpeechMs = 8000

    let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40))
    var scale: CGFloat { CGFloat(Settings.scalePercent) / 100 }
    var menuProvider: (() -> NSMenu)?

    private var micButton: KeyButton?
    private var backspaceButton: KeyButton?
    private var watcher: SilenceWatcher?
    private var popup: SymbolPopup?

    init() {
        build()
        if let origin = Settings.origin { panel.setFrameOrigin(origin) } else { placeDefault() }
        keepOnScreen()
        panel.orderFrontRegardless()
    }

    var isVisible: Bool { panel.isVisible }
    func toggle() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }

    func setScale(_ percent: Int) {
        Settings.scalePercent = percent
        popup?.close()
        let bottom = panel.frame.minY, left = panel.frame.minX
        build()
        panel.setFrameOrigin(NSPoint(x: left, y: bottom))   // bottom edge stays put
        keepOnScreen()
        save()
    }

    /// Creates the row of buttons at the current scale; runs again whenever the scale changes
    func build() {
        let s = scale
        let pad = 3 * s, gap = max(1, 2 * s)
        let height = 34 * s, width = 44 * s, gripWidth = 18 * s
        let total = NSSize(width: 2 * pad + (gripWidth + 2 * gap) + CGFloat(Self.keys.count) * (width + 2 * gap),
                           height: 2 * pad + height + 2 * gap)
        let background = KeyPanel.background(size: total, scale: s)

        let grip = GripView(frame: NSRect(x: pad + gap, y: pad + gap, width: gripWidth, height: height), scale: s)
        grip.onDragEnd = { [weak self] in self?.keepOnScreen(); self?.save() }
        grip.menuProvider = { [weak self] in self?.menuProvider?() ?? NSMenu() }
        background.addSubview(grip)

        var x = pad + gripWidth + 2 * gap
        for key in Self.keys {
            let button = KeyButton(symbol: key.symbol, text: key.text, tooltip: key.tip,
                                   frame: NSRect(x: x + gap, y: pad + gap, width: width, height: height), scale: s)
            switch key.kind {
            case .plain:
                let codes = key.keys.map { CGKeyCode($0) }
                button.onPress = { Keyboard.press(codes) }
            case .dictation:
                micButton = button
                button.onPress = { [weak self] in self?.toggleDictation() }
                if watcher != nil { button.fill = Palette.recording; button.hoverFill = Palette.recording }
            case .backspace:
                backspaceButton = button
                let codes = key.keys.map { CGKeyCode($0) }
                button.onMouseDown = { [weak self, weak button] event in
                    guard let self, let button else { return }
                    self.trackBackspace(button, event: event, keys: codes)
                }
            }
            background.addSubview(button)
            x += width + 2 * gap
        }

        panel.setContentSize(total)
        panel.contentView = background
        panel.invalidateShadow()
    }

    // MARK: Dictation with auto-stop

    /// First click starts OpenWhispr and listens to the mic; a pause (or a second click) stops it.
    func toggleDictation() {
        Keyboard.press(Settings.dictation.keys)
        if watcher != nil { stopWatching(); return }

        let watcher = SilenceWatcher(silenceMs: Self.silenceMs, noSpeechMs: Self.noSpeechMs)
        watcher.onQuiet = { [weak self] in
            Keyboard.press(Settings.dictation.keys)
            self?.stopWatching()
        }
        guard watcher.start() else { return }   // no microphone available: plain toggle
        self.watcher = watcher
        micButton?.fill = Palette.recording
        micButton?.hoverFill = Palette.recording
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        micButton?.fill = Palette.button
        micButton?.hoverFill = Palette.hover
    }

    // MARK: Backspace: click deletes, long press opens the symbol column

    private func trackBackspace(_ button: KeyButton, event: NSEvent, keys: [CGKeyCode]) {
        guard let window = button.window else { return }
        button.pressed = true
        // Released before the long-press delay: a plain Backspace
        if let early = window.nextEvent(matching: [.leftMouseUp], until: Date(timeIntervalSinceNow: Self.longPress),
                                        inMode: .eventTracking, dequeue: true) {
            button.pressed = false
            if button.bounds.contains(button.convert(early.locationInWindow, from: nil)) { Keyboard.press(keys) }
            return
        }
        // Held: open the column and let the user slide onto a symbol, like a phone keyboard
        let popup = openPopup(above: button)
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            popup.highlight(at: NSEvent.mouseLocation)
            if next.type == .leftMouseUp { break }
        }
        button.pressed = false
        popup.releaseAt(NSEvent.mouseLocation)
    }

    @discardableResult
    func openPopup(above button: KeyButton) -> SymbolPopup {
        popup?.close()
        let popup = SymbolPopup(above: button, symbols: Self.backspaceSymbols, scale: scale)
        popup.onClose = { [weak self, weak popup] in if self?.popup === popup { self?.popup = nil } }
        self.popup = popup
        return popup
    }

    /// For the screenshot in CI: shows the symbol column with "?" highlighted and the mic as recording
    func showDemoState() {
        micButton?.fill = Palette.recording
        if let backspaceButton { openPopup(above: backspaceButton).highlightIndex(1) }
    }

    // MARK: Position

    private func placeDefault() {
        guard let screen = NSScreen.main else { return }
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.minY + 90))
    }

    /// Pulls the whole panel back inside its screen; the full frame counts, so it can sit over the Dock
    func keepOnScreen() {
        let screen = panel.screen ?? NSScreen.main
        guard let area = screen?.frame else { return }
        var origin = panel.frame.origin
        origin.x = max(area.minX, min(origin.x, area.maxX - panel.frame.width))
        origin.y = max(area.minY, min(origin.y, area.maxY - panel.frame.height))
        panel.setFrameOrigin(origin)
    }

    private func save() { Settings.origin = panel.frame.origin }
}
