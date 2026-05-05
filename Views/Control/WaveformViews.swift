import SwiftUI

// MARK: - Waveform Preview View

struct WaveformPreviewView: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    guard !points.isEmpty else { return }
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let midY = height / 2
                    for (index, value) in points.enumerated() {
                        let x = (Double(index) / Double(points.count - 1)) * width
                        let y = midY - (value * midY * 0.8)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: width, y: midY))
                    path.addLine(to: CGPoint(x: 0, y: midY))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                Path { path in
                    guard !points.isEmpty else { return }
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let midY = height / 2
                    for (index, value) in points.enumerated() {
                        let x = (Double(index) / Double(points.count - 1)) * width
                        let y = midY - (value * midY * 0.8)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(LinearGradient(colors: [.blue, .purple, .pink], startPoint: .leading, endPoint: .trailing), lineWidth: 2)
            }
        }
    }
}

// MARK: - Waveform Mini Preview

struct WaveformMiniPreview: View {
    let waveform: WaveformType
    let frequency: Double
    @State private var points: [Double] = []
    @State private var engine = WaveformEngine()

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !points.isEmpty else { return }
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2
                for (index, value) in points.enumerated() {
                    let x = (Double(index) / Double(points.count - 1)) * width
                    let y = midY - (value * midY * 0.8)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
        }
        .task {
            points = await engine.generate(waveform, samples: 200, frequency: frequency)
        }
    }
}

// MARK: - Waveform Editor View

struct WaveformEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var presetStore: PresetStore
    @State private var drawnPoints: [Double] = Array(repeating: 0, count: 100)
    @State private var name: String = "Custom Waveform"
    @State private var selectedPreset: QuickShape? = .none

    enum QuickShape: String, CaseIterable {
        case none = "Clear"
        case pulse = "Pulse"
        case doublePulse = "Dbl Pulse"
        case rampUp = "Ramp ↑"
        case sine = "Sine"
        case noise = "Noise"

        func generate() -> [Double] {
            switch self {
            case .none: return Array(repeating: 0, count: 100)
            case .pulse:
                var pts = Array(repeating: 0.0, count: 100)
                pts[45...54].indices.forEach { pts[$0] = 1 }
                return pts
            case .doublePulse:
                var pts = Array(repeating: 0.0, count: 100)
                pts[20...29].indices.forEach { pts[$0] = 1 }
                pts[70...79].indices.forEach { pts[$0] = 1 }
                return pts
            case .rampUp:
                return Array(stride(from: -1, through: 1, by: 2.0 / 99))
            case .sine:
                return (0..<100).map { i in sin(Double(i) / 100 * 4 * .pi) }
            case .noise:
                return (0..<100).map { _ in Double.random(in: -1...1) }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Draw Waveform").font(.headline)
                        GeometryReader { geometry in
                            ZStack {
                                ForEach(0..<5) { i in
                                    Path { path in
                                        let y = geometry.size.height * Double(i + 1) / 6
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                    }
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                                }
                                Path { path in
                                    let y = geometry.size.height / 2
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                }
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                                Path { path in
                                    let w = geometry.size.width
                                    let h = geometry.size.height
                                    for (i, v) in drawnPoints.enumerated() {
                                        let x = (Double(i) / Double(drawnPoints.count - 1)) * w
                                        let y = (h / 2) - (v * h / 2 * 0.9)
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                }
                                .stroke(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing), lineWidth: 3)

                                Rectangle().fill(Color.clear).contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                        let x = value.location.x / geometry.size.width
                                        let y = 1 - (value.location.y / geometry.size.height) * 2
                                        let idx = Int(x * Double(drawnPoints.count - 1))
                                        if idx >= 0 && idx < drawnPoints.count {
                                            drawnPoints[idx] = max(-1, min(1, y))
                                        }
                                    })
                            }
                        }
                        .frame(height: 200)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Shapes").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(QuickShape.allCases, id: \.self) { shape in
                                    Button {
                                        selectedPreset = shape
                                        if shape == .none { drawnPoints = shape.generate() }
                                        else { drawnPoints = shape.generate() }
                                    } label: {
                                        Text(shape.rawValue)
                                            .font(.caption).padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(selectedPreset == shape ? Color.accentColor : Color.secondary.opacity(0.15))
                                            .foregroundColor(selectedPreset == shape ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    TextField("Waveform name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
            }
            .navigationTitle("Waveform Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = Preset(
                            name: name,
                            icon: "pencil",
                            color: "#BF5AF2",
                            channelA: .init(strength: 30, waveform: .custom(name: name, points: drawnPoints), frequency: 20, pulseWidth: 200, phaseOffset: 0, durationMs: 0)
                        )
                        presetStore.savePreset(saved)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Channel Detail View

struct ChannelDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM
    let channel: ChannelState
    let isA: Bool

    private var ch: ChannelState { channel }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    detailCard("Strength") {
                        Text("\(Int(ch.strength))%")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(isA ? .blue : .purple)
                        Slider(value: binding(.strength), in: 0...100)
                            .tint(isA ? .blue : .purple)
                    }

                    detailCard("Waveform") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
                            ForEach(WaveformType.allBuiltIn) { wf in
                                Button {
                                    update { $0.waveform = wf }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: wf.icon).font(.title2)
                                        Text(wf.name).font(.caption2).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(ch.waveform.id == wf.id ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    sliderCard("Frequency", binding(.frequency), unit: "Hz", range: 1...50, color: .orange)
                    sliderCard("Pulse Width", Binding(
                        get: { Double(ch.pulseWidth) },
                        set: { update { $0.pulseWidth = Int($0) } }
                    ), unit: "μs", range: 50...1000, color: .pink)
                    sliderCard("Phase Offset", binding(.phaseOffset), unit: "°", range: 0...360, color: .teal)

                    detailCard("Duration") {
                        Picker("", selection: Binding(
                            get: { ch.durationMs },
                            set: { update { $0.durationMs = $0 } }
                        )) {
                            Text("Continuous").tag(0)
                            Text("10s").tag(10_000)
                            Text("30s").tag(30_000)
                            Text("1 min").tag(60_000)
                            Text("2 min").tag(120_000)
                            Text("5 min").tag(300_000)
                            Text("10 min").tag(600_000)
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Invert Output", isOn: binding(.isInverted))
                        .padding().glassCard()
                }
                .padding()
            }
            .navigationTitle("Channel \(ch.id.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
    }

    // MARK: - Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<ChannelState, T>) -> Binding<T> {
        Binding(
            get: { ch[keyPath: keyPath] },
            set: { update { $0[keyPath: keyPath] = $0 } }
        )
    }

    private func update(_ block: (inout ChannelState) -> Void) {
        if isA { controlVM.updateChannelA(block) }
        else { controlVM.updateChannelB(block) }
    }

    private func detailCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundColor(.secondary)
            content()
        }
        .padding().glassCard()
    }

    private func sliderCard(_ title: String, _ value: Binding<Double>, unit: String, range: ClosedRange<Double>, color: Color) -> some View {
        detailCard(title) {
            HStack {
                Slider(value: value, in: range).tint(color)
                Text("\(Int(value.wrappedValue))\(unit)")
                    .foregroundColor(.secondary).frame(width: 50).monospacedDigit()
            }
        }
    }
}
