import SwiftUI
import AppKit

/// In-app "Connectors" panel — shown from Settings or from the chat sidebar.
/// Walks the user through wiring Claude Desktop / Claude Code / Cursor /
/// ChatGPT to Ithuriel via the MCP server in services/mcp/.
struct ConnectorsView: View {
    let bearerToken: String
    let apiBaseURL: String

    @State private var tokenRevealed = false
    @State private var copyConfirm = false
    @State private var scriptCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                tokenCard

                clientCard(
                    name: "Claude Desktop",
                    detail: "Local stdio. One-shot install via the helper script — then restart Claude.",
                    icon: "macwindow",
                    tint: Color(red: 0.85, green: 0.60, blue: 0.40)
                )
                clientCard(
                    name: "Claude Code (CLI)",
                    detail: "Same MCP server. The installer writes to ~/.claude.json so Claude Code picks it up next launch.",
                    icon: "terminal",
                    tint: Color(red: 0.50, green: 0.40, blue: 0.95)
                )
                clientCard(
                    name: "Cursor",
                    detail: "Same MCP server, config at ~/.cursor/mcp.json. The installer handles it.",
                    icon: "cursorarrow.square",
                    tint: Color(red: 0.32, green: 0.85, blue: 0.70)
                )
                clientCard(
                    name: "ChatGPT (Developer mode)",
                    detail: "Remote HTTPS connector. Deploy to Cloud Run once, then ChatGPT → Settings → Connectors → Add custom connector. Paste the bearer token.",
                    icon: "globe",
                    tint: Color(red: 0.10, green: 0.65, blue: 0.45)
                )
                clientCard(
                    name: "Claude.ai (web)",
                    detail: "Same remote URL works. Settings → Connectors → Add custom connector → Bearer token.",
                    icon: "globe.americas.fill",
                    tint: Color(red: 0.95, green: 0.50, blue: 0.30)
                )
            }
            .padding(24)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Ithuriel")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("Ithuriel ships an MCP server that exposes your live workspace context to any AI client. One server, all of them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(.tint)
                Text("Bearer token")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Button(tokenRevealed ? "Hide" : "Reveal") {
                    withAnimation(Motion.easeOut) { tokenRevealed.toggle() }
                }
                .controlSize(.small)
                .buttonStyle(.pressable())
            }
            HStack(spacing: 8) {
                Text(tokenRevealed ? displayToken : String(repeating: "•", count: 24))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bearerToken, forType: .string)
                    withAnimation(Motion.easeOut) { copyConfirm = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(Motion.easeOut) { copyConfirm = false }
                    }
                } label: {
                    Label(copyConfirm ? "Copied" : "Copy", systemImage: copyConfirm ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.pressable(sound: .submit))
                .disabled(bearerToken.isEmpty)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            if bearerToken.isEmpty {
                Label("Sign in or paste a token in Integrations first.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func clientCard(name: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: icon).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Helpers

    private var displayToken: String {
        bearerToken.isEmpty ? "(no token yet)" : bearerToken
    }
}
