import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click-to-record hotkey picker. The button shows the current binding as a
/// glyph string ("⌃Space"). On click it goes into "listening" mode and the
/// next clean key+modifier chord becomes the new binding.
struct HotkeyPickerView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var listening = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { listening.toggle() }) {
                Text(listening
                     ? NSLocalizedString("settings.hotkey.listening", comment: "")
                     : HotkeyMonitor.glyph(keyCode: keyCode, modifiers: modifiers))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(listening
                                  ? Color.accentColor.opacity(0.12)
                                  : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(listening
                                          ? Color.accentColor
                                          : Color.primary.opacity(0.12),
                                          lineWidth: listening ? 1.5 : 0.5)
                    )
            }
            .buttonStyle(.plain)

            if !listening {
                Text(NSLocalizedString("settings.hotkey.click", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .background(KeyCaptureNSView(active: $listening) { newCode, newMods in
            keyCode = newCode
            modifiers = newMods
            listening = false
        })
    }
}

/// NSViewRepresentable that installs a local-key monitor while `active`.
/// Captures the next non-modifier key with at least one modifier and sends it
/// upward. ESC cancels.
private struct KeyCaptureNSView: NSViewRepresentable {
    @Binding var active: Bool
    var onCapture: (Int, Int) -> Void

    final class Coordinator {
        var monitor: Any?
        var onCapture: (Int, Int) -> Void
        var unbind: () -> Void
        init(onCapture: @escaping (Int, Int) -> Void, unbind: @escaping () -> Void) {
            self.onCapture = onCapture
            self.unbind = unbind
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, unbind: { self.active = false })
    }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        c.onCapture = onCapture
        if active && c.monitor == nil {
            c.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {  // ESC
                    if let m = c.monitor { NSEvent.removeMonitor(m); c.monitor = nil }
                    DispatchQueue.main.async { c.unbind() }
                    return nil
                }
                var mods = 0
                if event.modifierFlags.contains(.command)   { mods |= 1 }
                if event.modifierFlags.contains(.shift)     { mods |= 2 }
                if event.modifierFlags.contains(.option)    { mods |= 4 }
                if event.modifierFlags.contains(.control)   { mods |= 8 }
                guard mods != 0 else { return event }
                let code = Int(event.keyCode)
                c.onCapture(code, mods)
                if let m = c.monitor { NSEvent.removeMonitor(m); c.monitor = nil }
                return nil
            }
        } else if !active, let m = c.monitor {
            NSEvent.removeMonitor(m); c.monitor = nil
        }
    }
}
