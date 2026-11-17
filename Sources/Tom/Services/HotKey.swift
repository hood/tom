import AppKit
import Carbon.HIToolbox

/// Global hotkey through Carbon: no Accessibility permission needed.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private var current: HotKeyCombo?

    /// Returns false if the combo is taken by another app.
    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        current = combo
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x544F_4D21), id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    func suspend() { unregister() }
    func resume() { if let current { register(current) } }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

extension HotKeyCombo {
    static func from(_ e: NSEvent) -> HotKeyCombo? {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var mods: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); symbols += "⌘" }
        return HotKeyCombo(keyCode: UInt32(e.keyCode), modifiers: mods,
                           display: "\(symbols) \(keyName(e.keyCode, e.charactersIgnoringModifiers))")
    }

    static func keyName(_ code: UInt16, _ chars: String?) -> String {
        switch Int(code) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_Escape: "⎋"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_DownArrow: "↓"
        case kVK_UpArrow: "↑"
        default: (chars ?? "?").uppercased()
        }
    }
}
