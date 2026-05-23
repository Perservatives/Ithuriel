import AppKit
import SwiftUI

/// Top-centre banner shown for ~2.4s when the agent finishes a task. Uses a
/// borderless floating window so it overlays any frontmost app.
@MainActor
final class DoneBannerController {
    static let shared = DoneBannerController()
    private init() {}

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func showFinished(summary: String) { show(kind: .finished, summary: summary) }
    func showFailed(summary: String)   { show(kind: .failed,   summary: summary) }
    func showStopped(summary: String)  { show(kind: .stopped,  summary: summary) }

    private func show(kind: BannerKind, summary: String) {
        dismissTask?.cancel()

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: 360, height: 56)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 56
        )

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .floating
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window = w
        }
        window?.setFrame(NSRect(origin: origin, size: size), display: false)
        window?.contentView = NSHostingView(rootView: DoneBannerView(kind: kind, summary: summary))
        window?.orderFrontRegardless()

        // Also play the matching sound.
        switch kind {
        case .finished: SoundPlayer.shared.play(.done, volume: 0.55)
        case .failed:   SoundPlayer.shared.play(.dismiss, volume: 0.4)
        case .stopped:  SoundPlayer.shared.play(.dismiss, volume: 0.3)
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss() }
        }
    }

    private func dismiss() {
        // Fade out via the SwiftUI side then orderOut.
        if let host = window?.contentView as? NSHostingView<DoneBannerView> {
            host.rootView = DoneBannerView(kind: host.rootView.kind,
                                           summary: host.rootView.summary,
                                           visible: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }
}

enum BannerKind { case finished, failed, stopped }

struct DoneBannerView: View {
    let kind: BannerKind
    let summary: String
    var visible: Bool = true

    @State private var enter: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(colors: [Color.white.opacity(0.05), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.40), radius: 22, y: 10)
        .scaleEffect(visible ? (0.98 + 0.02 * enter) : 0.96)
        .opacity(visible ? enter : 0)
        .offset(y: visible ? (1 - enter) * -6 : -6)
        .onAppear {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.36)) {
                enter = 1
            }
        }
        .animation(.timingCurve(0.4, 0, 1, 1, duration: 0.32), value: visible)
    }

    private var headline: String {
        switch kind {
        case .finished: return "Done"
        case .failed:   return "Failed"
        case .stopped:  return "Stopped"
        }
    }

    private var icon: String {
        switch kind {
        case .finished: return "checkmark"
        case .failed:   return "xmark"
        case .stopped:  return "stop.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .finished: return .green
        case .failed:   return .red
        case .stopped:  return .orange
        }
    }
}
