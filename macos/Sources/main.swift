// VibeKeys for macOS: a small always-on-top panel with a few keyboard keys for mouse-and-voice use.
// Lives in the menu bar (no Dock icon). Build: ./build.sh

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: PanelController!
    private var statusItem: NSStatusItem!
    private let demo = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = PanelController()
        controller.menuProvider = { [weak self] in self?.panelMenu() ?? NSMenu() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "VibeKeys")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // "Hide Others" in another app hides us too; come straight back without taking focus
        NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            NSApp.unhideWithoutActivation()
        }

        if demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller.showDemoState() }
            return
        }
        applyAutostart(Settings.autostartWanted)
        if !Keyboard.trusted { Keyboard.askForPermission() }
    }

    // MARK: Menus

    /// Menu bar menu, rebuilt each time it opens so ticks are current
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(controller.isVisible ? "Скрыть панель" : "Показать панель") { [weak self] in self?.controller.toggle() })
        menu.addItem(scaleMenu())
        menu.addItem(dictationMenu())
        let autostart = item("Запускать при входе в систему") { [weak self] in
            Settings.autostartWanted.toggle()
            self?.applyAutostart(Settings.autostartWanted)
        }
        autostart.state = Settings.autostartWanted ? .on : .off
        menu.addItem(autostart)
        if !Keyboard.trusted {
            menu.addItem(.separator())
            menu.addItem(item("Разрешить управление клавиатурой…") { Keyboard.openAccessibilitySettings() })
        }
        menu.addItem(.separator())
        menu.addItem(item("Выход") { NSApp.terminate(nil) })
    }

    /// Right-click menu of the panel's drag handle
    private func panelMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(scaleMenu())
        menu.addItem(item("Скрыть панель") { [weak self] in self?.controller.toggle() })
        menu.addItem(item("Выход") { NSApp.terminate(nil) })
        return menu
    }

    private func scaleMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Масштаб", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for percent in Settings.scaleSteps {
            let entry = item("\(percent)%") { [weak self] in self?.controller.setScale(percent) }
            entry.state = percent == Settings.scalePercent ? .on : .off
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func dictationMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Сочетание для диктовки", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for hotkey in DictationHotkey.allCases {
            let entry = item(hotkey.title) { Settings.dictation = hotkey }
            entry.state = hotkey == Settings.dictation ? .on : .off
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, action: #selector(ClosureMenuItem.run), keyEquivalent: "")
        entry.handler = action
        entry.target = entry
        return entry
    }

    // MARK: Autostart

    /// Registers or removes VibeKeys as a login item (macOS 13+). Re-registering also follows a moved app.
    private func applyAutostart(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on, service.status != .enabled { try service.register() }
            if !on, service.status == .enabled { try service.unregister() }
        } catch {
            NSLog("VibeKeys: login item change failed: \(error)")
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    var handler: (() -> Void)?
    @objc func run() { handler?() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
