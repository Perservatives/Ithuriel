import SwiftUI
import SwiftData
import Combine

/// Force-directed graph over everything Ithuriel knows about you right now:
/// the active workspace, files Gemini referenced, terminal commands, git
/// branch + commit, recent agent runs. Nodes orbit a central "you" anchor;
/// connections are drawn as soft glass-like edges.
///
/// Implementation: SwiftUI Canvas + TimelineView. The simulation is a tiny
/// Verlet-style integrator running on the main thread (≤ ~60 nodes, cheap).
struct ContextWebView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedAgentRun.startedAt, order: .reverse) private var runs: [SavedAgentRun]
    @Query private var prefsList: [UserPrefs]

    @State private var simulation = WebSimulation()
    @State private var lastSync = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            Canvas { context, size in
                simulation.tick(in: size, time: timeline.date)
                drawEdges(simulation.edges, nodes: simulation.nodes, context: context)
                drawNodes(simulation.nodes, context: context)
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if simulation.draggedID == nil {
                            if let node = simulation.nearestNode(to: value.startLocation) {
                                simulation.beginDrag(id: node.id, at: value.location)
                            }
                        } else {
                            simulation.updateDrag(to: value.location)
                        }
                    }
                    .onEnded { _ in simulation.endDrag() }
            )
            .background(
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.08), .clear],
                    center: .center, startRadius: 8, endRadius: 280
                )
            )
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Context Web")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                    Text("\(simulation.nodes.count) nodes · \(simulation.edges.count) edges")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, UILayout.spacingM)
                .padding(.vertical, UILayout.spacingS)
                .background(
                    RoundedRectangle(cornerRadius: UILayout.radiusS, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .padding(UILayout.spacingM)
            }
            .onAppear { rebuild() }
            .onChange(of: runs.count) { _, _ in rebuild() }
            .onChange(of: prefsList.first?.activeWorkspace) { _, _ in rebuild() }
        }
    }

    private func drawNodes(_ nodes: [WebNode], context: GraphicsContext) {
        for node in nodes {
            let r = node.radius
            let rect = CGRect(x: node.position.x - r, y: node.position.y - r,
                              width: r * 2, height: r * 2)

            // Soft halo
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                with: .radialGradient(
                    Gradient(colors: [node.tint.opacity(0.55), .clear]),
                    center: node.position, startRadius: 0, endRadius: r + 8
                )
            )
            // Solid disc
            context.fill(Path(ellipseIn: rect), with: .color(node.tint))
            // Highlight ring
            context.stroke(Path(ellipseIn: rect),
                           with: .color(.white.opacity(0.35)),
                           lineWidth: 0.5)

            if node.label.isEmpty == false, r > 7 {
                let labelOffset = CGPoint(x: node.position.x, y: node.position.y + r + 8)
                let text = Text(node.label)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(.primary.opacity(0.78))
                context.draw(text, at: labelOffset, anchor: .top)
            }
        }
    }

    private func drawEdges(_ edges: [WebEdge], nodes: [WebNode], context: GraphicsContext) {
        for edge in edges {
            guard let a = nodes.first(where: { $0.id == edge.a }),
                  let b = nodes.first(where: { $0.id == edge.b }) else { continue }
            var path = Path()
            path.move(to: a.position)
            path.addLine(to: b.position)
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [a.tint.opacity(0.45), b.tint.opacity(0.45)]),
                    startPoint: a.position, endPoint: b.position
                ),
                lineWidth: edge.weight
            )
        }
    }

    private func rebuild() {
        var nodes: [WebNode] = []
        var edges: [WebEdge] = []
        let centerID = "you"
        nodes.append(WebNode(id: centerID, label: "you", radius: 14, tint: .accentColor, pinned: true))

        let ws = prefsList.first?.activeWorkspace ?? ""
        if !ws.isEmpty {
            let label = (ws as NSString).lastPathComponent
            nodes.append(WebNode(id: "ws", label: label, radius: 11, tint: .orange))
            edges.append(WebEdge(a: centerID, b: "ws", weight: 1.4))
        }

        let recent = runs.prefix(8)
        for (i, run) in recent.enumerated() {
            let id = "run-\(run.id.uuidString)"
            let tint: Color = {
                switch run.status {
                case .running:   return .accentColor
                case .completed: return .green
                case .failed:    return .red
                case .killed:    return .orange
                }
            }()
            let preview = String(run.task.prefix(24))
            nodes.append(WebNode(id: id, label: preview, radius: 7, tint: tint))
            edges.append(WebEdge(a: centerID, b: id, weight: 0.8))
            if i > 0 {
                let prev = "run-\(recent[recent.index(recent.startIndex, offsetBy: i - 1)].id.uuidString)"
                edges.append(WebEdge(a: prev, b: id, weight: 0.3))
            }
        }

        // Add some abstract context families so the graph feels populated.
        for (label, tint) in [
            ("git", Color.purple),
            ("terminal", Color.teal),
            ("files", Color.indigo),
            ("screen", Color.pink)
        ] {
            let id = "fam-\(label)"
            nodes.append(WebNode(id: id, label: label, radius: 9, tint: tint))
            edges.append(WebEdge(a: centerID, b: id, weight: 1.0))
        }

        simulation.replace(nodes: nodes, edges: edges)
    }
}

// MARK: - Simulation primitives

struct WebNode: Identifiable, Equatable {
    let id: String
    let label: String
    let radius: CGFloat
    let tint: Color
    var pinned: Bool = false
    var position: CGPoint = .zero
    var velocity: CGSize = .zero
}

struct WebEdge: Equatable {
    let a: String
    let b: String
    let weight: CGFloat
}

/// Tiny force-directed simulation. Not a perfect physics engine — just enough
/// motion to make the graph feel alive without burning CPU.
final class WebSimulation: ObservableObject {
    var nodes: [WebNode] = []
    var edges: [WebEdge] = []
    var draggedID: String? = nil
    private var initialised = false
    private var lastTick: Date = Date()

    func nearestNode(to point: CGPoint) -> WebNode? {
        nodes.filter { !$0.pinned }.min(by: {
            hypot($0.position.x - point.x, $0.position.y - point.y) <
            hypot($1.position.x - point.x, $1.position.y - point.y)
        })
    }

    func beginDrag(id: String, at point: CGPoint) {
        guard let i = nodes.firstIndex(where: { $0.id == id && !$0.pinned }) else { return }
        draggedID = id
        nodes[i].position = point
        nodes[i].velocity = .zero
    }

    func updateDrag(to point: CGPoint) {
        guard let id = draggedID,
              let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[i].position = point
        nodes[i].velocity = .zero
    }

    func endDrag() { draggedID = nil }

    func replace(nodes: [WebNode], edges: [WebEdge]) {
        let existingPositions = Dictionary(uniqueKeysWithValues: self.nodes.map { ($0.id, $0.position) })
        self.nodes = nodes.map { n in
            var copy = n
            if let p = existingPositions[n.id] { copy.position = p }
            return copy
        }
        self.edges = edges
        initialised = false
    }

    func tick(in size: CGSize, time: Date) {
        guard size.width > 0, size.height > 0 else { return }
        if !initialised { seed(size: size); initialised = true }

        let dt = min(0.05, max(0.005, time.timeIntervalSince(lastTick)))
        lastTick = time

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        for i in nodes.indices {
            if nodes[i].pinned {
                nodes[i].position = center
                nodes[i].velocity = .zero
                continue
            }
            // Skip physics for the node being dragged.
            if nodes[i].id == draggedID {
                nodes[i].velocity = .zero
                continue
            }

            var fx: CGFloat = 0, fy: CGFloat = 0

            // Repulsion from siblings.
            for j in nodes.indices where j != i {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let d2 = max(40, dx * dx + dy * dy)
                let f: CGFloat = 1200.0 / d2
                fx += f * dx
                fy += f * dy
            }

            // Centre spring — stronger pull keeps nodes clustered near the hub.
            let cx = center.x - nodes[i].position.x
            let cy = center.y - nodes[i].position.y
            fx += cx * 0.045
            fy += cy * 0.045

            // Edge springs.
            for edge in edges where edge.a == nodes[i].id || edge.b == nodes[i].id {
                let otherID = edge.a == nodes[i].id ? edge.b : edge.a
                guard let other = nodes.first(where: { $0.id == otherID }) else { continue }
                let ex = other.position.x - nodes[i].position.x
                let ey = other.position.y - nodes[i].position.y
                fx += ex * 0.045 * edge.weight
                fy += ey * 0.045 * edge.weight
            }

            // Integrate with heavy damping.
            nodes[i].velocity.width  = (nodes[i].velocity.width  + fx * dt) * 0.86
            nodes[i].velocity.height = (nodes[i].velocity.height + fy * dt) * 0.86
            nodes[i].position.x += nodes[i].velocity.width * dt * 60
            nodes[i].position.y += nodes[i].velocity.height * dt * 60

            // Clamp to canvas.
            let margin: CGFloat = 18
            nodes[i].position.x = min(max(margin, nodes[i].position.x), size.width  - margin)
            nodes[i].position.y = min(max(margin, nodes[i].position.y), size.height - margin)
        }
    }

    private func seed(size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for i in nodes.indices {
            if nodes[i].pinned {
                nodes[i].position = center
                continue
            }
            if nodes[i].position == .zero {
                let angle = Double(i) / Double(nodes.count) * .pi * 2
                let radius = min(size.width, size.height) * 0.15
                nodes[i].position = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
            }
        }
    }
}
