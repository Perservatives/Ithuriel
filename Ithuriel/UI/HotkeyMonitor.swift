import AppKit
import Carbon.HIToolbox
import SwiftData

/// Global hotkey dispatcher for Ithuriel.
///
/// User-configurable. Default is **⌃Space**: tap toggles the Spotlight prompt,
/// hold ≥320ms enters voice mode until release. The key code + modifier mask
/// are stored on `UserPrefs.hotkeyKeyCode` / `UserPrefs.hotkeyModifiers` and
/// `updateBinding(...)` is called by the Settings UI when changed.
///
/// Uses `CGEventTap` because Carbon `RegisterEventHotKey` only fires on
/// key-down and we need to measure how long the user holds before deciding
/// tap vs. hold. The tap is listen-only (does not consume the events).
@MainActor
final class HotkeyMonitor {
    static let shared = HotkeyMonitor()
    private init() {}

    /// Packed modifier mask matching UserPrefs.hotkeyModifiers.
    struct ModifierMask: OptionSet {
        let rawValue: Int
        static let cmd     = ModifierMask(rawValue: 1)
        static let shift   = ModifierMask(rawValue: 2)
        static let opt     = ModifierMask(rawValue: 4)
        static let ctrl    = ModifierMask(rawValue: 8)
    }

    var onSummonTap: () -> Void = {}
    var onVoiceStart: () -> Void = {}
    var onVoiceEnd: () -> Void = {}

    /// Active binding. Set via `updateBinding(...)` from settings or AppDelegate.
    private(set) var keyCode: Int = kVK_Space
    private(set) var modifiers: ModifierMask = .ctrl

    private let holdThresholdMillis: UInt64 = 320
    private var pressDownAt: UInt64 = 0
    private var pressed = false
    private var holdFired = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Update the active binding. Safe to call repeatedly; no-op if unchanged.
    func updateBinding(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = ModifierMask(rawValue: modifiers)
        // The event tap reads `keyCode` / `modifiers` every event, so no
        // restart needed. Carbon fallback needs re-registration though.
        if tap == nil {
            unregisterCarbon()
            installCarbonFallback()
        }
    }

    func install() {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.flagsChanged.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in monitor.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // CGEventTap requires Accessibility. Without it we still get
            // tap-to-summon via Carbon, but hold-to-talk is dead. Surface a
            // notification banner so the user knows to grant access.
            Log.info("HotkeyMonitor: CGEventTap denied — falling back to Carbon. Grant Accessibility for hold-to-talk.")
            DoneBannerController.shared.showFailed(
                summary: "Grant Accessibility in System Settings → Privacy → Accessibility so the shortcut works."
            )
            installCarbonFallback()
            return
        }

        self.tap = eventTap
        self.source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    // MARK: - Handler

    private func handle(type: CGEventType, event: CGEvent) {
        let evKey = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isClean = matchesModifiers(flags)
        switch type {
        case .keyDown:
            guard evKey == keyCode, !pressed, isClean else { return }
            beginPress()
        case .keyUp:
            guard evKey == keyCode, pressed else { return }
            endPress()
        case .flagsChanged:
            // Lost any required modifier while space was held → end press.
            if pressed && !matchesModifiers(flags) { endPress() }
        default:
            break
        }
    }

    private func matchesModifiers(_ flags: CGEventFlags) -> Bool {
        let needCmd   = modifiers.contains(.cmd)
        let needShift = modifiers.contains(.shift)
        let needOpt   = modifiers.contains(.opt)
        let needCtrl  = modifiers.contains(.ctrl)
        if needCmd   != flags.contains(.maskCommand)   { return false }
        if needShift != flags.contains(.maskShift)     { return false }
        if needOpt   != flags.contains(.maskAlternate) { return false }
        if needCtrl  != flags.contains(.maskControl)   { return false }
        // Allow modifier-free hotkeys (e.g. a function key) — the caller
        // (HotkeyPickerView) is responsible for not registering ambiguous
        // chords like a bare letter that would type into every text field.
        return true
    }

    private func beginPress() {
        pressed = true
        pressDownAt = nowMillis()
        holdFired = false

        let downStamp = pressDownAt
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard let self,
                  self.pressed,
                  self.pressDownAt == downStamp,
                  !self.holdFired else { return }
            self.holdFired = true
            self.onVoiceStart()
        }
    }

    private func endPress() {
        let wasHold = holdFired
        pressed = false
        pressDownAt = 0
        holdFired = false
        if wasHold {
            onVoiceEnd()
        } else {
            onSummonTap()
        }
    }

    private func nowMillis() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Carbon fallback (no Accessibility yet — tap=summon only)

    private var carbonHotKey: EventHotKeyRef?
    private var carbonHandlerRef: EventHandlerRef?

    private func installCarbonFallback() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x49544855), id: 3)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Only install the global event handler once. Previous implementations
        // re-installed on every rebind, leaking handlers each time.
        if carbonHandlerRef == nil {
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotkeyMonitor.shared.onSummonTap() }
                return noErr
            }, 1, &spec, nil, &carbonHandlerRef)
        }
        var carbonMods: UInt32 = 0
        if modifiers.contains(.cmd)   { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if modifiers.contains(.opt)   { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.ctrl)  { carbonMods |= UInt32(controlKey) }
        RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                            GetApplicationEventTarget(), 0, &carbonHotKey)
    }

    private func unregisterCarbon() {
        if let ref = carbonHotKey {
            UnregisterEventHotKey(ref)
            carbonHotKey = nil
        }
    }
}

// MARK: - Display helper

extension HotkeyMonitor {
    /// Render a key-binding as a glyph string like "⌃Space" or "⇧⌘K".
    static func glyph(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        let m = ModifierMask(rawValue: modifiers)
        if m.contains(.ctrl)  { s += "⌃" }
        if m.contains(.opt)   { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.cmd)   { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    private static func keyName(_ code: Int) -> String {
        switch code {
        case kVK_Space:       return "Space"
        case kVK_Return:      return "Return"
        case kVK_Tab:         return "Tab"
        case kVK_Escape:      return "Esc"
        case kVK_Delete:      return "⌫"
        case kVK_LeftArrow:   return "←"
        case kVK_RightArrow:  return "→"
        case kVK_UpArrow:     return "↑"
        case kVK_DownArrow:   return "↓"
        case kVK_F1:          return "F1"
        case kVK_F2:          return "F2"
        case kVK_F3:          return "F3"
        case kVK_F4:          return "F4"
        case kVK_F5:          return "F5"
        case kVK_F6:          return "F6"
        case kVK_F7:          return "F7"
        case kVK_F8:          return "F8"
        case kVK_F9:          return "F9"
        case kVK_F10:         return "F10"
        case kVK_F11:         return "F11"
        case kVK_F12:         return "F12"
        default:
            // Try to decode via TIS.
            if let scalar = unicodeForKeyCode(code) { return scalar.uppercased() }
            return "Key\(code)"
        }
    }

    private static func unicodeForKeyCode(_ code: Int) -> String? {
        let src = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutPtr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars: [UniChar] = Array(repeating: 0, count: 4)
        var realLength = 0
        let status = data.withUnsafeBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                base,
                UInt16(code),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &realLength,
                &chars
            )
        }
        guard status == noErr, realLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: realLength)
    }
}
