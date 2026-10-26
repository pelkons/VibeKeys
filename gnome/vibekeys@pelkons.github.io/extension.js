// VibeKeys for GNOME Shell: a small always-on-top panel with a few keyboard keys for mouse-and-voice use.
// The panel lives in the shell's own layer, so clicking it never takes focus from the window you are
// typing in, and its keys are sent through a virtual keyboard by physical key code (layout-independent).

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import Clutter from 'gi://Clutter';
import St from 'gi://St';
import Shell from 'gi://Shell';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {SilenceWatcher} from './silence.js';

// Linux evdev key codes (input-event-codes.h)
const KEY = {ESC: 1, BACKSPACE: 14, ENTER: 28, LEFTCTRL: 29, Z: 44, LEFTSHIFT: 42, LEFTALT: 56, SPACE: 57, SYSRQ: 99, LEFTMETA: 125};

// ---- Buttons, left to right. Icons are bundled (icons/vibekeys-<id>-symbolic.svg) so they look
// the same whatever icon theme is installed. ----
const BUTTONS = [
    {id: 'mic', kind: 'dictation'},
    {id: 'confirm', keys: [KEY.LEFTCTRL, KEY.ENTER]},
    {id: 'newline', keys: [KEY.LEFTSHIFT, KEY.ENTER]},
    {id: 'undo', keys: [KEY.LEFTCTRL, KEY.Z]},
    {id: 'esc', text: 'Esc', keys: [KEY.ESC]},
    {id: 'screenshot', keys: [KEY.SYSRQ]},
    {id: 'space', keys: [KEY.SPACE]},
    {id: 'enter', keys: [KEY.ENTER]},
    {id: 'backspace', keys: [KEY.BACKSPACE], kind: 'backspace'},
];

// Hotkey that starts and stops OpenWhispr dictation; pick the one set in OpenWhispr.
// Super goes first so the second key cancels it as the Activities key.
const DICTATION_HOTKEYS = {
    'ctrl+super': {title: 'Ctrl + Super (по умолчанию в OpenWhispr)', keys: [KEY.LEFTMETA, KEY.LEFTCTRL]},
    'super+alt': {title: 'Super + Alt', keys: [KEY.LEFTMETA, KEY.LEFTALT]},
};

const SCALE_STEPS = [30, 40, 60, 80, 100, 120, 140, 160, 180, 200];
const BACKSPACE_SYMBOLS = '.?,!';   // long press on Backspace; first one closest to the button
const LONG_PRESS_MS = 450;
const POPUP_CLOSE_MS = 1500;        // popup closes once the mouse has been away this long
const SILENCE_MS = 2000, NO_SPEECH_MS = 8000;

// ---- Settings: ~/.config/vibekeys/settings.json ----

const SETTINGS_FILE = GLib.build_filenamev([GLib.get_user_config_dir(), 'vibekeys', 'settings.json']);
const DEFAULT_SETTINGS = {scale: 100, dictation: 'ctrl+super', showAtLogin: true, x: null, y: null};

function loadSettings() {
    try {
        const [, contents] = GLib.file_get_contents(SETTINGS_FILE);
        const saved = JSON.parse(new TextDecoder().decode(contents));
        const settings = {...DEFAULT_SETTINGS, ...saved};
        if (!SCALE_STEPS.includes(settings.scale))
            settings.scale = 100;
        if (!(settings.dictation in DICTATION_HOTKEYS))
            settings.dictation = DEFAULT_SETTINGS.dictation;
        return settings;
    } catch (e) {
        return {...DEFAULT_SETTINGS};
    }
}

function saveSettings(settings) {
    try {
        GLib.mkdir_with_parents(GLib.path_get_dirname(SETTINGS_FILE), 0o755);
        GLib.file_set_contents(SETTINGS_FILE, JSON.stringify(settings, null, 2));
    } catch (e) {
        logError(e, 'VibeKeys: could not save settings');
    }
}

// Polls the pointer until the primary button is released. Mouse events during a hold go to whichever
// actor grabbed them, so (as on Windows) we read the pointer and button state directly instead.
function trackPrimaryButton(onMove, onRelease) {
    return GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, () => {
        const [x, y, mods] = global.get_pointer();
        if (mods & Clutter.ModifierType.BUTTON1_MASK) {
            onMove(x, y);
            return GLib.SOURCE_CONTINUE;
        }
        onRelease(x, y);
        return GLib.SOURCE_REMOVE;
    });
}

function contains(actor, x, y) {
    const [ax, ay] = actor.get_transformed_position();
    const [w, h] = actor.get_transformed_size();
    return x >= ax && x < ax + w && y >= ay && y < ay + h;
}

// A column of extra characters above a button, like the alternate-key popup on a phone keyboard.
class SymbolPopup {
    constructor(vibe, anchor, symbols, scale) {
        this._vibe = vibe;
        this._anchor = anchor;
        this._lastNear = GLib.get_monotonic_time();
        const gap = Math.max(1, Math.round(2 * scale));

        this.actor = new St.BoxLayout({
            style_class: 'vibekeys-popup', vertical: true, reactive: true,
            style: `padding: ${gap}px; border-radius: ${Math.round(10 * scale)}px;`,
        });
        this.buttons = [];
        const [w, h] = anchor.get_size();
        // BoxLayout stacks top to bottom; the first symbol belongs at the bottom, next to the button
        for (const character of [...symbols].reverse()) {
            const button = new St.Button({
                style_class: 'vibekeys-key', can_focus: false, track_hover: true, reactive: true,
                label: character,
                style: `width: ${w}px; height: ${h}px; margin: ${gap}px; border-radius: ${Math.round(6 * scale)}px; font-size: ${Math.round(16 * scale)}px;`,
            });
            button.connect('clicked', () => this.pick(character));
            this.actor.add_child(button);
            this.buttons.unshift({button, character});
        }
        Main.layoutManager.addChrome(this.actor, {affectsInputRegion: true});

        const [ax, ay] = anchor.get_transformed_position();
        const [, pw] = this.actor.get_preferred_width(-1);
        const [, ph] = this.actor.get_preferred_height(pw);
        let y = ay - 3 * gap - ph;
        if (y < 0)
            y = ay + h + 3 * gap;   // no room above: open downward
        this.actor.set_position(Math.round(ax - 2 * gap), Math.round(y));

        this._watchId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            const [px, py] = global.get_pointer();
            if (contains(this.actor, px, py) || contains(this._anchor, px, py))
                this._lastNear = GLib.get_monotonic_time();
            else if ((GLib.get_monotonic_time() - this._lastNear) / 1000 > POPUP_CLOSE_MS) {
                this._watchId = 0;
                this.close();
                return GLib.SOURCE_REMOVE;
            }
            return GLib.SOURCE_CONTINUE;
        });
    }

    highlightAt(x, y) {
        for (const {button} of this.buttons) {
            if (contains(button, x, y))
                button.add_style_class_name('vibekeys-highlight');
            else
                button.remove_style_class_name('vibekeys-highlight');
        }
    }

    // Mouse released after a long press: type the symbol under it, otherwise stay open for a click
    releaseAt(x, y) {
        const hit = this.buttons.find(({button}) => contains(button, x, y));
        if (hit)
            this.pick(hit.character);
        else
            this.highlightAt(-1, -1);
    }

    pick(character) {
        this._vibe.typeText(character);
        this.close();
    }

    close() {
        if (this._watchId)
            GLib.source_remove(this._watchId);
        this._watchId = 0;
        if (this.actor) {
            Main.layoutManager.removeChrome(this.actor);
            this.actor.destroy();
            this.actor = null;
        }
        this._vibe.popupClosed(this);
    }
}

const Indicator = GObject.registerClass(
class Indicator extends PanelMenu.Button {
    _init(vibe, iconPath) {
        super._init(0.0, 'VibeKeys');
        this._vibe = vibe;
        this.add_child(new St.Icon({gicon: Gio.icon_new_for_string(iconPath), style_class: 'system-status-icon'}));

        this._toggleItem = new PopupMenu.PopupMenuItem('');
        this._toggleItem.connect('activate', () => vibe.togglePanel());
        this.menu.addMenuItem(this._toggleItem);

        this._scaleItems = vibe.addScaleMenu(this.menu);

        const dictation = new PopupMenu.PopupSubMenuMenuItem('Сочетание для диктовки');
        this._dictationItems = Object.entries(DICTATION_HOTKEYS).map(([id, {title}]) => {
            const item = new PopupMenu.PopupMenuItem(title);
            item.connect('activate', () => vibe.setDictation(id));
            dictation.menu.addMenuItem(item);
            return [id, item];
        });
        this.menu.addMenuItem(dictation);

        this._loginItem = new PopupMenu.PopupSwitchMenuItem('Показывать панель при входе', vibe.settings.showAtLogin);
        this._loginItem.connect('toggled', (_item, state) => vibe.setShowAtLogin(state));
        this.menu.addMenuItem(this._loginItem);

        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this.refresh();
        });
        this.refresh();
    }

    refresh() {
        this._toggleItem.label.text = this._vibe.panelVisible ? 'Скрыть панель' : 'Показать панель';
        this._vibe.refreshScaleMenu(this._scaleItems);
        for (const [id, item] of this._dictationItems)
            item.setOrnament(id === this._vibe.settings.dictation ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        this._loginItem.setToggleState(this._vibe.settings.showAtLogin);
    }
});

class VibeKeys {
    constructor(extension) {
        this._extension = extension;
        this.settings = loadSettings();
        this._sources = new Set();
        const seat = Clutter.get_default_backend().get_default_seat();
        this._keyboard = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);

        this._buildPanel();
        if (!this.settings.showAtLogin)
            this._panel.hide();

        this._indicator = new Indicator(this, `${extension.path}/icons/vibekeys-symbolic.svg`);
        Main.panel.addToStatusArea('vibekeys', this._indicator);

        if (GLib.getenv('VIBEKEYS_TEST'))
            this._exportTestInterface();
    }

    destroy() {
        this._watcher?.stop();
        this._watcher = null;
        this._popup?.close();
        for (const id of this._sources)
            GLib.source_remove(id);
        this._sources.clear();
        this._gripMenu?.destroy();
        this._destroyPanel();
        this._indicator?.destroy();
        this._indicator = null;
        this._testExport?.unexport();
        if (this._testNameId)
            Gio.bus_unown_name(this._testNameId);
        this._keyboard = null;
        this._pointer = null;
    }

    get panelVisible() {
        return this._panel.visible;
    }

    togglePanel() {
        if (this._panel.visible)
            this._panel.hide();
        else
            this._panel.show();
    }

    // ---- Keys ----

    // Presses keys together (modifiers first), holds them briefly so global-hotkey listeners such as
    // OpenWhispr see the combo, then releases them in reverse order.
    press(keys) {
        const time = GLib.get_monotonic_time();
        for (const key of keys)
            this._keyboard.notify_key(time, key, Clutter.KeyState.PRESSED);
        this._later(50, () => {
            const later = GLib.get_monotonic_time();
            for (const key of [...keys].reverse())
                this._keyboard?.notify_key(later, key, Clutter.KeyState.RELEASED);
        });
    }

    // Types characters by key symbol; the shell adds Shift where the current layout needs it
    typeText(text) {
        for (const character of text) {
            const keyval = Clutter.unicode_to_keysym(character.codePointAt(0));
            const time = GLib.get_monotonic_time();
            this._keyboard.notify_keyval(time, keyval, Clutter.KeyState.PRESSED);
            this._keyboard.notify_keyval(time + 1, keyval, Clutter.KeyState.RELEASED);
        }
    }

    _later(ms, callback) {
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._sources.delete(id);
            callback();
            return GLib.SOURCE_REMOVE;
        });
        this._sources.add(id);
        return id;
    }

    _cancel(id) {
        if (id && this._sources.delete(id))
            GLib.source_remove(id);
    }

    // ---- Panel ----

    _buildPanel() {
        const s = this.settings.scale / 100;
        const gap = Math.max(1, Math.round(2 * s));
        this._panel = new St.BoxLayout({
            style_class: 'vibekeys-panel', reactive: true,
            style: `padding: ${Math.round(3 * s)}px; border-radius: ${Math.round(10 * s)}px;`,
        });
        this.buttons = {};
        const keyStyle = (width) =>
            `width: ${Math.round(width * s)}px; height: ${Math.round(34 * s)}px; margin: ${gap}px; ` +
            `border-radius: ${Math.round(6 * s)}px; font-size: ${Math.round(14 * s)}px;`;

        // Drag handle: left button drags, right button opens the menu
        const grip = new St.Button({
            style_class: 'vibekeys-grip', can_focus: false, reactive: true, button_mask: 0,
            style: keyStyle(18),
            child: new St.Icon({
                gicon: this._icon('grip'), icon_size: Math.round(14 * s),
                x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.CENTER,
            }),
        });
        grip.connect('button-press-event', (_actor, event) => {
            if (event.get_button() === Clutter.BUTTON_SECONDARY)
                this._gripMenu.toggle();
            else if (event.get_button() === Clutter.BUTTON_PRIMARY)
                this._startDrag();
            return Clutter.EVENT_STOP;
        });
        this._panel.add_child(grip);
        this._grip = grip;

        for (const def of BUTTONS) {
            const align = {x_align: Clutter.ActorAlign.CENTER, y_align: Clutter.ActorAlign.CENTER};
            const child = def.text
                ? new St.Label({text: def.text, ...align})
                : new St.Icon({gicon: this._icon(def.id), icon_size: Math.round(18 * s), ...align});
            const button = new St.Button({
                style_class: 'vibekeys-key', can_focus: false, track_hover: true, reactive: true,
                style: keyStyle(44), child,
            });
            if (def.kind === 'dictation') {
                button.connect('clicked', () => this.toggleDictation());
                if (this._watcher)
                    button.add_style_class_name('vibekeys-recording');
            } else if (def.kind === 'backspace') {
                button.connect('button-press-event', (_actor, event) => {
                    if (event.get_button() !== Clutter.BUTTON_PRIMARY)
                        return Clutter.EVENT_PROPAGATE;
                    this._backspacePressed(button, def.keys);
                    return Clutter.EVENT_STOP;
                });
            } else {
                button.connect('clicked', () => this.press(def.keys));
            }
            this._panel.add_child(button);
            this.buttons[def.id] = button;
        }

        Main.layoutManager.addChrome(this._panel, {affectsInputRegion: true});
        this._buildGripMenu();
        this._placePanel();
    }

    _icon(name) {
        return Gio.icon_new_for_string(`${this._extension.path}/icons/vibekeys-${name}-symbolic.svg`);
    }

    _destroyPanel() {
        if (!this._panel)
            return;
        Main.layoutManager.removeChrome(this._panel);
        this._panel.destroy();
        this._panel = null;
    }

    _buildGripMenu() {
        this._gripMenu?.destroy();
        this._gripMenu = new PopupMenu.PopupMenu(this._grip, 0.0, St.Side.BOTTOM);
        Main.uiGroup.add_child(this._gripMenu.actor);
        this._gripMenu.actor.hide();
        this._gripMenuManager = new PopupMenu.PopupMenuManager(this._panel);
        this._gripMenuManager.addMenu(this._gripMenu);

        const scaleItems = this.addScaleMenu(this._gripMenu);
        this._gripMenu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this.refreshScaleMenu(scaleItems);
        });
        const hide = new PopupMenu.PopupMenuItem('Скрыть панель');
        hide.connect('activate', () => this._panel.hide());
        this._gripMenu.addMenuItem(hide);
    }

    _placePanel() {
        const monitor = Main.layoutManager.primaryMonitor;
        const [, width] = this._panel.get_preferred_width(-1);
        const [, height] = this._panel.get_preferred_height(width);
        let {x, y} = this.settings;
        if (x === null || y === null) {
            x = monitor.x + (monitor.width - width) / 2;
            y = monitor.y + monitor.height - height - 80;
        }
        this._panel.set_position(Math.round(x), Math.round(y));
        this._keepOnScreen(width, height);
    }

    // Pulls the whole panel back inside the monitor it is on
    _keepOnScreen(width = this._panel.width, height = this._panel.height) {
        const cx = this._panel.x + width / 2, cy = this._panel.y + height / 2;
        const monitor = Main.layoutManager.monitors.find(m =>
            cx >= m.x && cx < m.x + m.width && cy >= m.y && cy < m.y + m.height) ?? Main.layoutManager.primaryMonitor;
        const x = Math.max(monitor.x, Math.min(this._panel.x, monitor.x + monitor.width - width));
        const y = Math.max(monitor.y, Math.min(this._panel.y, monitor.y + monitor.height - height));
        this._panel.set_position(Math.round(x), Math.round(y));
    }

    _startDrag() {
        const [startX, startY] = global.get_pointer();
        const [panelX, panelY] = [this._panel.x, this._panel.y];
        const id = trackPrimaryButton(
            (x, y) => this._panel.set_position(panelX + x - startX, panelY + y - startY),
            () => {
                this._sources.delete(id);
                this._keepOnScreen();
                this.settings.x = this._panel.x;
                this.settings.y = this._panel.y;
                saveSettings(this.settings);
            });
        this._sources.add(id);
    }

    // ---- Scale ----

    addScaleMenu(menu) {
        const scale = new PopupMenu.PopupSubMenuMenuItem('Масштаб');
        const items = SCALE_STEPS.map(percent => {
            const item = new PopupMenu.PopupMenuItem(`${percent}%`);
            item.connect('activate', () => this.setScale(percent));
            scale.menu.addMenuItem(item);
            return [percent, item];
        });
        menu.addMenuItem(scale);
        return items;
    }

    refreshScaleMenu(items) {
        for (const [percent, item] of items)
            item.setOrnament(percent === this.settings.scale ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
    }

    setScale(percent) {
        this.settings.scale = percent;
        // Rebuild once the menu that triggered this has closed: it belongs to the panel being replaced
        this._later(0, () => {
            this._popup?.close();
            const visible = this._panel.visible;
            const bottom = this._panel.y + this._panel.height;
            const left = this._panel.x;
            this._gripMenu?.destroy();
            this._gripMenu = null;
            this._destroyPanel();
            this._buildPanel();
            const [, width] = this._panel.get_preferred_width(-1);
            const [, height] = this._panel.get_preferred_height(width);
            this._panel.set_position(left, bottom - height);   // bottom edge stays put
            this._keepOnScreen(width, height);
            this.settings.x = this._panel.x;
            this.settings.y = this._panel.y;
            if (!visible)
                this._panel.hide();
            saveSettings(this.settings);
        });
    }

    setDictation(id) {
        this.settings.dictation = id;
        saveSettings(this.settings);
    }

    setShowAtLogin(on) {
        this.settings.showAtLogin = on;
        saveSettings(this.settings);
    }

    // ---- Dictation with auto-stop ----

    // First click starts OpenWhispr and listens to the mic; a pause (or a second click) stops it.
    toggleDictation() {
        const keys = DICTATION_HOTKEYS[this.settings.dictation].keys;
        this.press(keys);
        if (this._watcher) {
            this._stopWatching();
            return;
        }
        const watcher = new SilenceWatcher(SILENCE_MS, NO_SPEECH_MS, () => {
            this.press(keys);
            this._stopWatching();
        });
        if (!watcher.start())
            return;   // no recorder available: plain toggle
        this._watcher = watcher;
        this.buttons.mic.add_style_class_name('vibekeys-recording');
    }

    _stopWatching() {
        this._watcher?.stop();
        this._watcher = null;
        this.buttons?.mic?.remove_style_class_name('vibekeys-recording');
    }

    // ---- Backspace: click deletes, long press opens the symbol column ----

    _backspacePressed(button, keys) {
        button.add_style_pseudo_class('active');
        let opened = false;
        const hold = this._later(LONG_PRESS_MS, () => {
            opened = true;
            this._openPopup(button);
        });
        const id = trackPrimaryButton(
            (x, y) => {
                if (opened)
                    this._popup?.highlightAt(x, y);
            },
            (x, y) => {
                this._sources.delete(id);
                button.remove_style_pseudo_class('active');
                if (!opened) {
                    this._cancel(hold);
                    if (contains(button, x, y))
                        this.press(keys);
                } else {
                    this._popup?.releaseAt(x, y);
                }
            });
        this._sources.add(id);
    }

    _openPopup(button) {
        this._popup?.close();
        this._popup = new SymbolPopup(this, button, BACKSPACE_SYMBOLS, this.settings.scale / 100);
        return this._popup;
    }

    popupClosed(popup) {
        if (this._popup === popup)
            this._popup = null;
    }

    // ---- Test hooks: only when the shell runs with VIBEKEYS_TEST=1 (see gnome/test) ----

    _exportTestInterface() {
        const xml = `<node><interface name="io.github.pelkons.VibeKeys.Test">
            <method name="HideOverview"/>
            <method name="Center"><arg type="s" direction="in" name="id"/>
                <arg type="i" direction="out" name="x"/><arg type="i" direction="out" name="y"/></method>
            <method name="TypeText"><arg type="s" direction="in" name="text"/></method>
            <method name="PointerMove"><arg type="i" direction="in" name="x"/><arg type="i" direction="in" name="y"/></method>
            <method name="PointerButton"><arg type="b" direction="in" name="down"/></method>
            <method name="Screenshot"><arg type="s" direction="in" name="path"/></method>
            </interface></node>`;
        const seat = Clutter.get_default_backend().get_default_seat();
        this._pointer = seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE);
        const vibe = this;
        this._testExport = Gio.DBusExportedObject.wrapJSObject(xml, {
            HideOverview() {
                Main.overview.hide();
            },
            // id: a button id ("backspace") or "popup:N" for the N-th symbol, counted from the button
            Center(id) {
                const actor = id.startsWith('popup:')
                    ? vibe._popup?.buttons[Number(id.slice(6))]?.button
                    : vibe.buttons[id];
                if (!actor)
                    return [-1, -1];
                const [x, y] = actor.get_transformed_position();
                const [w, h] = actor.get_transformed_size();
                return [Math.round(x + w / 2), Math.round(y + h / 2)];
            },
            TypeText(text) {
                vibe.typeText(text);
            },
            PointerMove(x, y) {
                vibe._pointer.notify_absolute_motion(GLib.get_monotonic_time(), x, y);
            },
            PointerButton(down) {
                vibe._pointer.notify_button(GLib.get_monotonic_time(), Clutter.BUTTON_PRIMARY,
                    down ? Clutter.ButtonState.PRESSED : Clutter.ButtonState.RELEASED);
            },
            Screenshot(path) {
                const stream = Gio.File.new_for_path(path).replace(null, false, Gio.FileCreateFlags.NONE, null);
                new Shell.Screenshot().screenshot(false, stream, (shooter, result) => {
                    try {
                        shooter.screenshot_finish(result);
                    } catch (e) {
                        logError(e, 'VibeKeys test: screenshot failed');
                    }
                    stream.close(null);
                });
            },
        });
        this._testExport.export(Gio.DBus.session, '/io/github/pelkons/VibeKeys/Test');
        this._testNameId = Gio.bus_own_name_on_connection(Gio.DBus.session, 'io.github.pelkons.VibeKeys.Test',
            Gio.BusNameOwnerFlags.NONE, null, null);
    }
}

export default class VibeKeysExtension extends Extension {
    enable() {
        this._vibe = new VibeKeys(this);
    }

    disable() {
        this._vibe?.destroy();
        this._vibe = null;
    }
}
