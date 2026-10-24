// Persistent preferences, kept in UserDefaults (io.github.pelkons.vibekeys).

import AppKit
import Carbon.HIToolbox

/// Hotkey that starts and stops OpenWhispr dictation. OpenWhispr's own default is Control+Command;
/// pick whatever is set in OpenWhispr.
enum DictationHotkey: String, CaseIterable {
    case controlCommand = "ctrl+cmd"
    case commandOption = "cmd+option"
    case fn = "fn"

    var title: String {
        switch self {
        case .controlCommand: return "Control + Command (по умолчанию в OpenWhispr)"
        case .commandOption: return "Command + Option"
        case .fn: return "Fn / Globe"
        }
    }

    var keys: [CGKeyCode] {
        switch self {
        case .controlCommand: return [CGKeyCode(kVK_Control), CGKeyCode(kVK_Command)]
        case .commandOption: return [CGKeyCode(kVK_Command), CGKeyCode(kVK_Option)]
        case .fn: return [CGKeyCode(kVK_Function)]
        }
    }
}

enum Settings {
    /// Panel size choices, percent of normal
    static let scaleSteps = [30, 40, 60, 80, 100, 120, 140, 160, 180, 200]

    private static let defaults = UserDefaults.standard

    static var scalePercent: Int {
        get {
            let value = defaults.integer(forKey: "scale")
            return scaleSteps.contains(value) ? value : 100
        }
        set { defaults.set(newValue, forKey: "scale") }
    }

    /// Bottom-left corner of the panel on screen
    static var origin: NSPoint? {
        get { defaults.string(forKey: "origin").map(NSPointFromString) }
        set { defaults.set(newValue.map(NSStringFromPoint), forKey: "origin") }
    }

    static var dictation: DictationHotkey {
        get { DictationHotkey(rawValue: defaults.string(forKey: "dictation") ?? "") ?? .controlCommand }
        set { defaults.set(newValue.rawValue, forKey: "dictation") }
    }

    /// Autostart is on unless the user turned it off in the menu bar menu
    static var autostartWanted: Bool {
        get { defaults.object(forKey: "autostart") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autostart") }
    }
}
