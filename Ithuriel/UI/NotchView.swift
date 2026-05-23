import SwiftUI
import AppKit

/// The widget that lives in the notch. Collapsed it looks like an extension of
/// the notch itself — a black pill hugging the camera housing with the
/// asterisk mark + status dot inside. Hover or an active agent run expands it
/// downward to ~360pt × 80pt to show the agent's current narration.
///
/// Animation rules (Emil / Motion.swift): 240ms `cubic-bezier(0.23, 1, 0.32, 1)`
/// for the grow, `ease-out` because the element is entering. Respect
/// `accessibilityReduceMotion` — snap instead of animate. We only animate
/// `transform`-equivalents (frame/scale/opacity); no layout-thrashing properties.
struct NotchView: View {
    @ObservedObject private var bus = AgentStatusBus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    /// True when the panel should be in its tall, content-bearing state.
    private var expanded: Bool { hovered || bus.isRunning }

    /// Punchy ease-out at 240ms, matching the Motion token. Honors
    /// reduce-motion by collapsing to a 0-duration step.
    private var growth: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The notch-hugging surface. Pure black so it visually merges with
            // the actual notch; rounded only on the bottom corners so it looks
            // like it grew *out of* the notch rather than sitting under it.
            NotchShape(cornerRadius: expanded ? 18 : 10)
                .fill(Color.black)
                .frame(
                    width: expanded ? 360 : 220,
                    height: expanded ? 80 : max(notchHeight, 32)
                )
                .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 18, y: 6)

            // Content layer, clipped to the shape so nothing leaks out of the
            // black mass during the grow.
            content
                .frame(
                    width: expanded ? 360 : 220,
                    height: expanded ? 80 : max(notchHeight, 32)
                )
                .clipShape(NotchShape(cornerRadius: expanded ? 18 : 10))
        }
        .animation(growth, value: expanded)
        .onHover { isHovering in
            // Tracking-area driven; tiny debounce isn't necessary because
            // NSPanel.ignoresMouseEvents is false and the rect is small.
            hovered = isHovering
        }
        .onTapGesture { openChat() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ithuriel")
        .accessibilityValue(bus.lastSpoken ?? (bus.isRunning ? "Working" : "Idle"))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if expanded {
            expandedContent
                .transition(.opacity)
        } else {
            collapsedContent
                .transition(.opacity)
        }
    }

    private var collapsedContent: some View {
        // Tight cluster centred horizontally inside the notch outline. The
        // mark sits slightly above centre because the notch's safe area
        // includes the camera bezel.
        HStack(spacing: 6) {
            AsteriskMark(size: 10, tint: .white.opacity(0.85))
            StatusDot(state: dotState)
        }
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var expandedContent: some View {
        HStack(spacing: 10) {
            AsteriskMark(size: 14, tint: .white.opacity(0.9))

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: openChat) {
                Text("…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Open chat")
        }
        .padding(.horizontal, 14)
        .padding(.top, max(notchHeight, 6))
        .padding(.bottom, 8)
    }

    // MARK: - Derived UI state

    private var notchHeight: CGFloat {
        NotchDetector.notchHeight() ?? 32
    }

    private var headline: String {
        if let line = bus.lastSpoken, !line.isEmpty { return line }
        return bus.isRunning ? "Working…" : "Ithuriel"
    }

    private var subtitle: String? {
        bus.isRunning ? "Tap ⋯ for chat" : nil
    }

    private var dotState: StatusDot.State {
        if bus.isRunning { return .working }
        return .idle
    }

    // MARK: - Actions

    private func openChat() {
        NSApp.activate(ignoringOtherApps: true)
        AppRouter.shared.openChat()
    }
}

// MARK: - NotchShape

/// A rounded-bottom rectangle that mimics the notch silhouette. The top edge
/// is flat (it butts up against the screen edge) and only the bottom corners
/// are rounded, which is what makes it read as *part of* the notch.
private struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - StatusDot

private struct StatusDot: View {
    enum State { case idle, working, listening }
    let state: State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .shadow(color: color.opacity(0.6), radius: 3)
    }

    private var color: Color {
        switch state {
        case .idle:      return Color.white.opacity(0.30)
        case .working:   return Color(red: 0.40, green: 0.85, blue: 0.55)
        case .listening: return Color(red: 1.00, green: 0.45, blue: 0.55)
        }
    }
}
