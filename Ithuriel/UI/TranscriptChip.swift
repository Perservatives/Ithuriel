import SwiftUI

/// ChatGPT/Claude-style collapsed tool-call summary. By default shows a
/// single pill like "Used 4 tools · click to expand". Expanded, it renders
/// each tool line in muted monospace. Hidden entirely at verbosity 0
/// (summary-only) when there's a final ✓ line in the transcript.
struct TranscriptChip: View {
    let transcript: [String]
    /// 0 = summary only, 1 = answer + chip, 2 = always expanded.
    let verbosity: Int

    @State private var expanded = false

    var body: some View {
        let tool   = transcript.filter { $0.hasPrefix("→") }
        let done   = transcript.last { $0.hasPrefix("✓") }
        let failed = transcript.last { $0.hasPrefix("✗") || $0.hasPrefix("◌") }
        let thinking = transcript.last { $0.hasPrefix("·") }

        VStack(alignment: .leading, spacing: 8) {
            if verbosity == 0 {
                if let final = done ?? failed {
                    finalLine(final)
                }
            } else {
                if !tool.isEmpty || verbosity == 2 {
                    chip(toolCount: tool.count)
                    if expanded || verbosity == 2 {
                        expandedList(tool)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                if let t = thinking, done == nil && failed == nil {
                    Text(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if let final = done ?? failed {
                    finalLine(final)
                }
            }
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22), value: expanded)
    }

    private func chip(toolCount n: Int) -> some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .medium))
                Text(n == 0
                     ? NSLocalizedString("chip.thinking", comment: "")
                     : String(format: NSLocalizedString("chip.usedTools", comment: ""), n))
                    .font(.system(size: 12.5, weight: .medium))
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.55)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule().fill(Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func expandedList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 10)
    }

    private func finalLine(_ line: String) -> some View {
        let symbol: String
        let tint: Color
        if line.hasPrefix("✓") {
            symbol = "checkmark.circle.fill"; tint = .green
        } else if line.hasPrefix("✗") {
            symbol = "xmark.circle.fill"; tint = .red
        } else {
            symbol = "circle.dashed"; tint = .secondary
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
