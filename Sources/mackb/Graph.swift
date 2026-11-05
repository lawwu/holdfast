import SwiftUI

/// Force-directed layout: every pair repels, links pull like springs, and a
/// weak pull keeps everything near the centre. It cools as it settles and
/// warms up again while a node is dragged. O(n²) per frame is fine for a few
/// hundred notes.
final class GraphSim {
    var ids: [String] = []
    var pos: [CGPoint] = []
    var vel: [CGVector] = []
    var edges: [(Int, Int)] = []
    var degree: [Int] = []
    var neighbors: [Set<Int>] = []
    var alpha = 1.0
    var fixed: Int?

    static let linkLength = 80.0
    static let repulsion = 3400.0

    init() {}

    init(ids: [String], edges raw: [(String, String)]) {
        self.ids = ids
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var seen = Set<String>()
        for (a, b) in raw {
            guard let i = index[a], let j = index[b], i != j else { continue }
            let key = i < j ? "\(i)-\(j)" : "\(j)-\(i)"
            if seen.insert(key).inserted { edges.append((i, j)) }
        }
        degree = Array(repeating: 0, count: ids.count)
        neighbors = Array(repeating: [], count: ids.count)
        for (a, b) in edges {
            degree[a] += 1; degree[b] += 1
            neighbors[a].insert(b); neighbors[b].insert(a)
        }
        // Start on a spiral so the first frames already look tidy.
        pos = ids.indices.map { i in
            let r = 14.0 * sqrt(Double(i) + 1), t = Double(i) * 2.399963
            return CGPoint(x: r * cos(t), y: r * sin(t))
        }
        vel = Array(repeating: .zero, count: ids.count)
    }

    var settled: Bool { alpha < 0.004 }

    func step() {
        guard !settled else { return }
        let n = pos.count
        var f = Array(repeating: CGVector.zero, count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                var dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                if dx == 0 && dy == 0 { dx = Double.random(in: -1...1); dy = Double.random(in: -1...1) }
                let d2 = max(dx * dx + dy * dy, 25)
                let k = Self.repulsion / d2
                let d = sqrt(d2)
                f[i].dx += dx / d * k; f[i].dy += dy / d * k
                f[j].dx -= dx / d * k; f[j].dy -= dy / d * k
            }
        }
        for (a, b) in edges {
            let dx = pos[b].x - pos[a].x, dy = pos[b].y - pos[a].y
            let d = max(sqrt(dx * dx + dy * dy), 1)
            let k = (d - Self.linkLength) * 0.06
            f[a].dx += dx / d * k; f[a].dy += dy / d * k
            f[b].dx -= dx / d * k; f[b].dy -= dy / d * k
        }
        for i in 0..<n {
            f[i].dx -= pos[i].x * 0.012; f[i].dy -= pos[i].y * 0.012
            if i == fixed { vel[i] = .zero; continue }
            vel[i].dx = (vel[i].dx + f[i].dx * alpha) * 0.55
            vel[i].dy = (vel[i].dy + f[i].dy * alpha) * 0.55
            pos[i].x += max(-30, min(30, vel[i].dx))
            pos[i].y += max(-30, min(30, vel[i].dy))
        }
        alpha *= 0.985
    }

    /// Bounds of the layout, for fitting it to the view.
    var bounds: CGRect {
        guard let f = pos.first else { return .zero }
        var r = CGRect(origin: f, size: .zero)
        for p in pos { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -40, dy: -40)
    }
}

struct GraphView: View {
    @EnvironmentObject var store: Store
    @State private var sim = GraphSim()
    @State private var local = false
    @State private var orphans = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var dragNode: Int?
    @State private var hovered: Int?
    @State private var tick = 0

    var key: String {
        "\(local)-\(orphans)-\(local ? store.opened?.note.id ?? "" : "")-\(store.notes.count)-\(store.links.edgeCount)"
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            TimelineView(.animation(paused: sim.settled && dragNode == nil)) { _ in
                let _ = sim.step()
                Canvas { ctx, _ in draw(ctx, center: center) }
            }
            .contentShape(Rectangle())
            .gesture(drag(center: center))
            .simultaneousGesture(MagnifyGesture()
                .onChanged { scale = max(0.2, min(5, baseScale * $0.magnification)) }
                .onEnded { _ in baseScale = scale })
            .onContinuousHover { phase in
                if case .active(let p) = phase { hovered = hit(p, center: center) } else { hovered = nil }
            }
            .overlay(alignment: .topLeading) { legend.padding(14) }
            .overlay(alignment: .topTrailing) { controls(geo.size).padding(14) }
            .overlay(alignment: .bottomLeading) { hoverCard.padding(14) }
            .task(id: key) { rebuild(); fit(geo.size) }
        }
        .background(Theme.canvas)
        .navigationTitle("Graph")
    }

    // MARK: model

    func rebuild() {
        var nodeIds: [String]
        var edges: [(String, String)] = []
        for (a, outs) in store.links.outgoing { for b in outs { edges.append((a, b)) } }
        if local, let c = store.opened?.note.id {
            var keep: Set<String> = [c]
            let n1 = Set((store.links.outgoing[c] ?? []) + (store.links.incoming[c] ?? []))
            keep.formUnion(n1)
            for x in n1 { keep.formUnion((store.links.outgoing[x] ?? []) + (store.links.incoming[x] ?? [])) }
            nodeIds = Array(keep)
        } else {
            let linked = Set(edges.flatMap { [$0.0, $0.1] })
            nodeIds = store.notes.map(\.id).filter { orphans || linked.contains($0) }
        }
        nodeIds.sort()
        sim = GraphSim(ids: nodeIds, edges: edges)
        for _ in 0..<120 { sim.step() }  // pre-settle off screen
        tick += 1
    }

    func fit(_ size: CGSize) {
        let b = sim.bounds
        guard b.width > 0, b.height > 0 else { return }
        scale = max(0.25, min(2.5, min(size.width / b.width, size.height / b.height) * 0.9))
        baseScale = scale
        offset = CGSize(width: -b.midX * scale, height: -b.midY * scale)
    }

    func screen(_ p: CGPoint, _ c: CGPoint) -> CGPoint {
        CGPoint(x: c.x + p.x * scale + offset.width, y: c.y + p.y * scale + offset.height)
    }
    func world(_ p: CGPoint, _ c: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - c.x - offset.width) / scale, y: (p.y - c.y - offset.height) / scale)
    }
    func radius(_ i: Int) -> CGFloat { 3.5 + sqrt(CGFloat(sim.degree[i])) * 1.8 }

    func hit(_ p: CGPoint, center: CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        for i in sim.pos.indices {
            let s = screen(sim.pos[i], center)
            let d = hypot(s.x - p.x, s.y - p.y)
            if d <= max(radius(i) * scale, 6) + 3, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    // MARK: drawing

    func draw(_ ctx: GraphicsContext, center: CGPoint) {
        let current = store.opened?.note.id
        let focus = hovered ?? sim.ids.firstIndex(where: { $0 == current })
        let near = focus.map { sim.neighbors[$0].union([$0]) }
        // Edges
        for (a, b) in sim.edges {
            var path = Path()
            path.move(to: screen(sim.pos[a], center))
            path.addLine(to: screen(sim.pos[b], center))
            let lit = focus != nil && (a == focus || b == focus)
            ctx.stroke(path, with: .color(lit ? Theme.accent.opacity(0.75) : Color.primary.opacity(near == nil ? 0.13 : 0.05)),
                       lineWidth: lit ? 1.4 : 0.8)
        }
        // Nodes
        let topDegree = Set(sim.degree.enumerated().sorted { $0.element > $1.element }.prefix(6).map(\.offset))
        for i in sim.pos.indices {
            let p = screen(sim.pos[i], center)
            let r = radius(i) * min(max(scale, 0.6), 1.6)
            let note = store.links.byId[sim.ids[i]]
            let color = domainColor(note?.domain ?? "·")
            let dim = near.map { !$0.contains(i) } ?? false
            let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(dim ? 0.25 : 0.95)))
            if sim.ids[i] == current {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(Theme.accent), lineWidth: 2)
            }
            let showLabel = i == focus || (near?.contains(i) ?? false) || scale > 1.5 || (near == nil && topDegree.contains(i))
            if showLabel, let note {
                ctx.draw(Text(note.title).font(.system(size: 11, weight: i == focus ? .semibold : .regular))
                            .foregroundStyle(dim ? Color.secondary.opacity(0.5) : Color.primary.opacity(0.85)),
                         at: CGPoint(x: p.x, y: p.y + r + 8), anchor: .top)
            }
        }
    }

    // MARK: interaction

    func drag(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragNode == nil && panStart == nil {
                    if let i = hit(v.startLocation, center: center) { dragNode = i; sim.fixed = i }
                    else { panStart = offset }
                }
                if let i = dragNode, hypot(v.translation.width, v.translation.height) > 3 {
                    sim.pos[i] = world(v.location, center)
                    sim.alpha = max(sim.alpha, 0.25)
                } else if let s = panStart {
                    offset = CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height)
                }
            }
            .onEnded { v in
                if let i = dragNode, hypot(v.translation.width, v.translation.height) <= 3,
                   let n = store.links.byId[sim.ids[i]] {
                    store.openNote(n)
                }
                sim.fixed = nil
                dragNode = nil
                panStart = nil
            }
    }

    // MARK: chrome

    var legend: some View {
        let counts = Dictionary(grouping: sim.ids.compactMap { store.links.byId[$0]?.domain ?? "·" }, by: { $0 }).mapValues(\.count)
        let domains = counts.keys.sorted { counts[$0]! > counts[$1]! }.prefix(10)
        return VStack(alignment: .leading, spacing: 5) {
            Text("\(sim.ids.count) notes · \(sim.edges.count) links").font(.caption.weight(.semibold))
            ForEach(Array(domains), id: \.self) { d in
                HStack(spacing: 6) {
                    Circle().fill(domainColor(d)).frame(width: 8, height: 8)
                    Text(d == "·" ? "(root)" : d).font(.caption)
                    Text("\(counts[d]!)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
    }

    func controls(_ size: CGSize) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Picker("", selection: $local) {
                Text("Whole vault").tag(false)
                Text("Around this note").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(store.opened == nil && !local)
            HStack(spacing: 6) {
                Toggle("Unlinked notes", isOn: $orphans).toggleStyle(.checkbox).font(.caption).disabled(local)
                Button { scale = max(0.2, scale / 1.25); baseScale = scale } label: { Image(systemName: "minus.magnifyingglass") }
                Button { scale = min(5, scale * 1.25); baseScale = scale } label: { Image(systemName: "plus.magnifyingglass") }
                Button { fit(size) } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }.help("Fit")
                Button { sim.alpha = 1 } label: { Image(systemName: "wand.and.rays") }.help("Re-run the layout")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
    }

    @ViewBuilder var hoverCard: some View {
        if let i = hovered, sim.ids.indices.contains(i), let n = store.links.byId[sim.ids[i]] {
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title).font(.callout.weight(.semibold))
                Text(n.relPath).font(.caption).foregroundStyle(.secondary)
                Text("\(store.links.incoming[n.id]?.count ?? 0) backlinks · \(store.links.outgoing[n.id]?.count ?? 0) links · click to open")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        }
    }
}
