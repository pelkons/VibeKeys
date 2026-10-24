// Sends key presses to whatever app has keyboard focus. Needs the Accessibility permission
// (System Settings → Privacy & Security → Accessibility).

import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Keyboard {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility settings
    static func askForPermission() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func modifierFlag(_ key: CGKeyCode) -> CGEventFlags? {
        switch Int(key) {
        case kVK_Command, kVK_RightCommand: return .maskCommand
        case kVK_Shift, kVK_RightShift: return .maskShift
        case kVK_Option, kVK_RightOption: return .maskAlternate
        case kVK_Control, kVK_RightControl: return .maskControl
        case kVK_Function: return .maskSecondaryFn
        default: return nil
        }
    }

    /// Presses keys together (modifiers first), holds them briefly so global-hotkey listeners
    /// such as OpenWhispr see the combo, then releases them in reverse order.
    static func press(_ keys: [CGKeyCode]) {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        for key in keys {
            if let flag = modifierFlag(key) { flags.insert(flag) }
            post(source, key, down: true, flags: flags)
        }
        usleep(50_000)
        for key in keys.reversed() {
            if let flag = modifierFlag(key) { flags.remove(flag) }
            post(source, key, down: false, flags: flags)
        }
    }

    /// Types text as characters rather than keys, so it comes out right in any keyboard layout
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func post(_ source: CGEventSource?, _ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
