import AppKit
import Carbon.HIToolbox

/// Global hotkey dispatcher for Ithuriel.
///
/// - **⌃Space** — tap to summon the Spotlight prompt (toggle on/off).
/// - **⌥Space** — tap to open the full Chat desktop window. Hold (≥ 350ms)
///   while keeping the modifier down to switch into voice mode for the
///   duration of the hold; release to send the captured utterance.
///
/// Uses `CGEventTap` because Carbon `RegisterEventHotKey` only fires on
/// key-down and we need to measure how long the user holds before deciding
/// tap vs. hold. The tap is listen-only (does not consume the events) for
/// matched chords; everything else passes through untouched.
@MainActor
final class HotkeyMonitor {
    static let shared = HotkeyMonitor()
    private init() {}

    var onSummonTap: () -> Void = {}
    var onChatTap: () -> Void = {}
    var onVoiceStart: () -> Void = {}
    var onVoiceEnd: () -> Void = {}

    private let holdThresholdMillis: UInt64 = 350
    private var pressDownAt: UInt64 = 0
    private var pressedChord: Chord = .none
    private var holdFired = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    enum Chord { case none, summon, chat }

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
        switch type {
        case .keyDown:
            guard keyCode == kVK_Space, pressedChord == .none else { return }
            if flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskShift) {
                beginPress(.summon)
            } else if flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskShift) {
                beginPress(.chat)
            }
        case .keyUp:
            guard keyCode == kVK_Space else { return }
            endPress()
        case .flagsChanged:
            // Released the modifier without lifting space → treat as end.
            let lostControl = pressedChord == .summon && !flags.contains(.maskControl)
            let lostOption  = pressedChord == .chat    && !flags.contains(.maskAlternate)
            if lostControl || lostOption { endPress() }
        default:
            break
        }
    }

    private func beginPress(_ chord: Chord) {
        pressedChord = chord
        pressDownAt = nowMillis()
        holdFired = false

        // After the hold threshold elapses, if the chord is still down and
        // it's the chat chord, switch into voice mode.
        let chordSnapshot = chord
        let downStamp = pressDownAt
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self,
                  self.pressedChord == chordSnapshot,
                  self.pressDownAt == downStamp,
                  !self.holdFired else { return }
            self.holdFired = true
            if chordSnapshot == .chat { self.onVoiceStart() }
        }
    }

    private func endPress() {
        let chord = pressedChord
        let wasHold = holdFired
        pressedChord = .none
        pressDownAt = 0
        holdFired = false
        switch chord {
        case .summon:
            if !wasHold { onSummonTap() }
        case .chat:
            if wasHold { onVoiceEnd() } else { onChatTap() }
        case .none:
            break
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
