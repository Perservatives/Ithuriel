import AppKit
import Carbon.HIToolbox

/// Global hotkey ⌃⌥⌘. (control-option-command-period) — instantly stops the
/// running agent loop. Registered for the lifetime of the app.
final class KillSwitch {
    static let shared = KillSwitch()
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func install() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x49544855 /* 'ITHU' */), id: 1)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(),
                            { _, _, _ in
                                Task { @MainActor in
                                    AgentController.shared.kill()
                                    if !HackathonConfig.skipPermissionPrompts {
                                        NSSound(named: NSSound.Name("Submarine"))?.play()
                                    }
                                }
                                return noErr
                            }, 1, &spec, nil, &handlerRef)

        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let keyCode = UInt32(kVK_ANSI_Period)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
