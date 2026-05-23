import AppKit
import Carbon.HIToolbox

/// Global hotkey dispatcher for Ithuriel.
///
/// - **⌃Space (tap)** — toggle the Spotlight prompt from anywhere.
/// - **⌃Space (hold ≥ 320ms)** — voice mode while held; release submits the
///   transcribed utterance.
///
/// ⌃Space is also macOS's default "Select previous input source" shortcut. If
/// you have multiple input sources, the system shortcut fires alongside ours
/// (this tap is listen-only). Disable it in System Settings → Keyboard →
/// Keyboard Shortcuts → Input Sources to silence the side-effect.
///
/// Uses `CGEventTap` because Carbon `RegisterEventHotKey` only fires on
/// key-down and we need to measure how long the user holds before deciding
/// tap vs. hold. The tap is listen-only (does not consume the events).
@MainActor
final class HotkeyMonitor {
    static let shared = HotkeyMonitor()
    private init() {}

    var onSummonTap: () -> Void = {}
    var onVoiceStart: () -> Void = {}
    var onVoiceEnd: () -> Void = {}

    private let holdThresholdMillis: UInt64 = 320
    private var pressDownAt: UInt64 = 0
    private var pressed = false
    private var holdFired = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

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
            // Accessibility not granted yet — fall back to the Carbon hotkey.
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
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        // Exactly Control held, no Command/Option/Shift — so this doesn't
        // collide with ⇧⌃Space, ⌘⌃Space, ⌥⌃Space etc.
        let isClean = flags.contains(.maskControl)
                   && !flags.contains(.maskCommand)
                   && !flags.contains(.maskAlternate)
                   && !flags.contains(.maskShift)
        switch type {
        case .keyDown:
            guard keyCode == kVK_Space, !pressed, isClean else { return }
            beginPress()
        case .keyUp:
            guard keyCode == kVK_Space, pressed else { return }
            endPress()
        case .flagsChanged:
            // Released Control without lifting Space → treat as end.
            if pressed && !flags.contains(.maskControl) {
                endPress()
            }
        default:
            break
        }
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

    // MARK: - Fallback (no Accessibility yet)

    private var carbonHotKey: EventHotKeyRef?
    private func installCarbonFallback() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x49544855), id: 3)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotkeyMonitor.shared.onSummonTap() }
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &carbonHotKey)
    }
}
