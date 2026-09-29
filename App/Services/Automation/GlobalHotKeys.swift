import Carbon
import Foundation

/// Registers the user's keyboard shortcuts with the system, so they work whichever app is in
/// front. Carbon's hot keys need no Accessibility permission and deliver only the registered
/// combinations; no other keystroke reaches the app.
@MainActor
final class GlobalHotKeys {
    var onPress: (@MainActor (HotKeyAction) -> Void)?

    private let preferences: HotKeyPreferences
    private var handler: EventHandlerRef?
    private var registered: [HotKeyAction: EventHotKeyRef] = [:]
    private var observer: NSObjectProtocol?
    /// Marks the app's own hot keys in the events the system sends back ("WMKY").
    private static let signature: OSType = 0x574D_4B59

    init(preferences: HotKeyPreferences) {
        self.preferences = preferences
    }

    func start() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                guard status == noErr else { return status }
                let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot keys on the main thread's event loop.
                return MainActor.assumeIsolated { hotKeys.fire(pressed) }
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            AppLog.error("keyboard shortcuts could not listen for presses (\(status))")
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: HotKeyPreferences.didChangeNotification, object: preferences, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    /// Registers exactly the saved shortcuts, recording any the system refuses.
    private func sync() {
        for action in HotKeyAction.allCases {
            let wanted = preferences.bindings[action]
            if let ref = registered.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
            guard let wanted else {
                preferences.recordFailure(nil, for: action)
                continue
            }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                wanted.keyCode, wanted.modifiers, EventHotKeyID(signature: Self.signature, id: action.identifier),
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[action] = ref
                preferences.recordFailure(nil, for: action)
            } else {
                AppLog.warn("keyboard shortcut \(wanted.label) for \(action.rawValue) was refused (\(status))")
                preferences.recordFailure(
                    status == OSStatus(eventHotKeyExistsErr)
                        ? String(localized: "Another app already uses this shortcut. Record a different one.")
                        : String(localized: "macOS did not accept this shortcut (error \(Int(status))). Record a different one."),
                    for: action)
            }
        }
    }

    private func fire(_ pressed: EventHotKeyID) -> OSStatus {
        guard pressed.signature == Self.signature,
              let action = HotKeyAction.allCases.first(where: { $0.identifier == pressed.id })
        else { return OSStatus(eventNotHandledErr) }
        onPress?(action)
        return noErr
    }

    /// The shortcut a key press in the panel names: `code` is the page's `KeyboardEvent.code`,
    /// the key's position, as Carbon's key codes are. A key needs ⌘, ⌥ or ⌃ with it, so a
    /// shortcut never takes a key away from typing; only F13 to F20, which type nothing, may
    /// stand alone.
    static func hotKey(code: String, command: Bool, option: Bool, control: Bool, shift: Bool) throws -> HotKey {
        guard let key = keys[code] else {
            throw AutomationError(message: String(localized: "This key can’t be used for a shortcut. Try a letter, a number or a function key."))
        }
        let bare = ["F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20"].contains(code)
        guard command || option || control || bare else {
            throw AutomationError(message: String(localized: "Hold ⌘, ⌥ or ⌃ with the key, so the shortcut doesn’t take it away from typing."))
        }
        var modifiers = 0
        var label = ""
        if control { modifiers |= controlKey; label += "⌃" }
        if option { modifiers |= optionKey; label += "⌥" }
        if shift { modifiers |= shiftKey; label += "⇧" }
        if command { modifiers |= cmdKey; label += "⌘" }
        return HotKey(keyCode: UInt32(key.code), modifiers: UInt32(modifiers), label: label + key.label)
    }

    /// `KeyboardEvent.code` names and the Carbon key codes of the same positions.
    private static let keys: [String: (code: Int, label: String)] = [
        "KeyA": (kVK_ANSI_A, "A"), "KeyB": (kVK_ANSI_B, "B"), "KeyC": (kVK_ANSI_C, "C"),
        "KeyD": (kVK_ANSI_D, "D"), "KeyE": (kVK_ANSI_E, "E"), "KeyF": (kVK_ANSI_F, "F"),
        "KeyG": (kVK_ANSI_G, "G"), "KeyH": (kVK_ANSI_H, "H"), "KeyI": (kVK_ANSI_I, "I"),
        "KeyJ": (kVK_ANSI_J, "J"), "KeyK": (kVK_ANSI_K, "K"), "KeyL": (kVK_ANSI_L, "L"),
        "KeyM": (kVK_ANSI_M, "M"), "KeyN": (kVK_ANSI_N, "N"), "KeyO": (kVK_ANSI_O, "O"),
        "KeyP": (kVK_ANSI_P, "P"), "KeyQ": (kVK_ANSI_Q, "Q"), "KeyR": (kVK_ANSI_R, "R"),
        "KeyS": (kVK_ANSI_S, "S"), "KeyT": (kVK_ANSI_T, "T"), "KeyU": (kVK_ANSI_U, "U"),
        "KeyV": (kVK_ANSI_V, "V"), "KeyW": (kVK_ANSI_W, "W"), "KeyX": (kVK_ANSI_X, "X"),
        "KeyY": (kVK_ANSI_Y, "Y"), "KeyZ": (kVK_ANSI_Z, "Z"),
        "Digit0": (kVK_ANSI_0, "0"), "Digit1": (kVK_ANSI_1, "1"), "Digit2": (kVK_ANSI_2, "2"),
        "Digit3": (kVK_ANSI_3, "3"), "Digit4": (kVK_ANSI_4, "4"), "Digit5": (kVK_ANSI_5, "5"),
        "Digit6": (kVK_ANSI_6, "6"), "Digit7": (kVK_ANSI_7, "7"), "Digit8": (kVK_ANSI_8, "8"),
        "Digit9": (kVK_ANSI_9, "9"),
        "Minus": (kVK_ANSI_Minus, "-"), "Equal": (kVK_ANSI_Equal, "="),
        "BracketLeft": (kVK_ANSI_LeftBracket, "["), "BracketRight": (kVK_ANSI_RightBracket, "]"),
        "Backslash": (kVK_ANSI_Backslash, "\\"), "Semicolon": (kVK_ANSI_Semicolon, ";"),
        "Quote": (kVK_ANSI_Quote, "'"), "Comma": (kVK_ANSI_Comma, ","), "Period": (kVK_ANSI_Period, "."),
        "Slash": (kVK_ANSI_Slash, "/"), "Backquote": (kVK_ANSI_Grave, "`"),
        "Space": (kVK_Space, "Space"), "Enter": (kVK_Return, "↩"),
        "ArrowLeft": (kVK_LeftArrow, "←"), "ArrowRight": (kVK_RightArrow, "→"),
        "ArrowUp": (kVK_UpArrow, "↑"), "ArrowDown": (kVK_DownArrow, "↓"),
        "Home": (kVK_Home, "↖"), "End": (kVK_End, "↘"), "PageUp": (kVK_PageUp, "⇞"), "PageDown": (kVK_PageDown, "⇟"),
        "F1": (kVK_F1, "F1"), "F2": (kVK_F2, "F2"), "F3": (kVK_F3, "F3"), "F4": (kVK_F4, "F4"),
        "F5": (kVK_F5, "F5"), "F6": (kVK_F6, "F6"), "F7": (kVK_F7, "F7"), "F8": (kVK_F8, "F8"),
        "F9": (kVK_F9, "F9"), "F10": (kVK_F10, "F10"), "F11": (kVK_F11, "F11"), "F12": (kVK_F12, "F12"),
        "F13": (kVK_F13, "F13"), "F14": (kVK_F14, "F14"), "F15": (kVK_F15, "F15"), "F16": (kVK_F16, "F16"),
        "F17": (kVK_F17, "F17"), "F18": (kVK_F18, "F18"), "F19": (kVK_F19, "F19"), "F20": (kVK_F20, "F20"),
    ]
}
