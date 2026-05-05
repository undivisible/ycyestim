import SwiftUI

// MARK: - Waveform Preview View (polished with gradient fill)

struct WaveformPreviewView: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Filled area
                Path { path in
                    guard !points.isEmpty else { return }
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let midY = height / 2

                    for (index, value) in points.enumerated() {
                        let x = (Double(index) / Double(points.count - 1)) * width
                        let y = midY - (value * midY * 0.8)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: width, y: midY))
                    path.addLine(to: CGPoint(x: 0, y: midY))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.2), .purple.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line
                Path { path in
                    guard !points.isEmpty else { return }
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let midY = height / 2

                    for (index, value) in points.enumerated() {
                        let x = (Double(index) / Double(points.count - 1)) * width
                        let y = midY - (value * midY * 0.8)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
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
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
        }
        .task {
            let generated = await engine.generate(waveform, samples: 200, frequency: frequency)
            points = generated
        }
    }
}

// MARK: - Waveform Editor View (Apple-style)

struct WaveformEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var drawnPoints: [Double] = Array(repeating: 0, count: 100)
    @State private var name: String = "Custom Waveform"
    @State private var selectedPreset: WaveformPreset? = .pulseSingle

    enum WaveformPreset: String, CaseIterable {
        case pulseSingle = "Pulse"
        case pulseDouble = "Double Pulse"
        case ramp = "Ramp"
        case sine = "Sine"
        case noise = "Noise"

        func apply(to points: inout [Double]) {
            switch self {
            case .pulseSingle:
                points = Array(repeating: 0, count: 100)
                points[45...54].indices.forEach { points[$0] = 1 }
            case .pulseDouble:
                points = Array(repeating: 0, count: 100)
                points[20...29].indices.forEach { points[$0] = 1 }
                points[70...79].indices.forEach { points[$0] = 1 }
            case .ramp:
                points = Array(stride(from: -1, through: 1, by: 2.0 / 99))
            case .sine:
                points = (0..<100).map { i in sin(Double(i) / 100 * 4 * .pi) }
            case .noise:
                points = (0..<100).map { _ in Double.random(in: -1...1) }
            }
        }
    }

    var onSave: ((WaveformType) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Drawing canvas
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Draw Waveform")
                            .font(.headline)

                        GeometryReader { geometry in
                            ZStack {
                                // Grid
                                ForEach(0..<5) { i in
                                    Path { path in
                                        let y = geometry.size.height * Double(i + 1) / 6
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                    }
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                                }

                                // Center line
                                Path { path in
                                    let y = geometry.size.height / 2
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                }
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                                // Waveform
                                Path { path in
                                    let width = geometry.size.width
                                    let height = geometry.size.height
                                    for (i, value) in drawnPoints.enumerated() {
                                        let x = (Double(i) / Double(drawnPoints.count - 1)) * width
                                        let y = (height / 2) - (value * height / 2 * 0.9)
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                }
                                .stroke(
                                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 3
                                )

                                // Touch overlay
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let x = value.location.x / geometry.size.width
                                                let y = 1 - (value.location.y / geometry.size.height) * 2
                                                let index = Int(x * Double(drawnPoints.count - 1))
                                                if index >= 0 && index < drawnPoints.count {
                                                    drawnPoints[index] = max(-1, min(1, y))
                                                }
                                            }
                                    )
                            }
                        }
                        .frame(height: 200)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Quick presets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Shapes")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(WaveformPreset.allCases, id: \.self) { preset in
                                    Button {
                                        selectedPreset = preset
                                        preset.apply(to: &drawnPoints)
                                    } label: {
                                        Text(preset.rawValue)
                                            .font(.caption)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedPreset == preset
                                                    ? Color.accentColor
                                                    : Color.secondary.opacity(0.15)
                                            )
                                            .foregroundColor(selectedPreset == preset ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                }

                                Button {
                                    drawnPoints = Array(repeating: 0, count: 100)
                                    selectedPreset = nil
                                } label: {
                                    Image(systemName: "eraser")
                                        .font(.caption)
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }

                    // Name
                    TextField("Waveform name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
            }
            .navigationTitle("Waveform Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave?(.custom(name: name, points: drawnPoints))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Channel Detail View (Apple-style)

struct ChannelDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM
    let channel: ChannelState
    let isA: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Strength
                    detailCard("Strength") {
                        VStack {
                            Text("\(Int(channel.strength))%")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundColor(isA ? .blue : .purple)
                            Slider(value: Binding(
                                get: { channel.strength },
                                set: { v in isA ? controlVM.updateChannelA { $0.strength = v } : controlVM.updateChannelB { $0.strength = v } }
                            ), in: 0...100)
                            .tint(isA ? .blue : .purple)
                        }
                        .padding(.vertical, 8)
                    }

                    // Waveform grid
                    detailCard("Waveform") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
                            ForEach(WaveformType.allBuiltIn) { wf in
                                Button {
                                    isA ? controlVM.updateChannelA { $0.waveform = wf } : controlVM.updateChannelB { $0.waveform = wf }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: wf.icon)
                                            .font(.title2)
                                        Text(wf.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        channel.waveform.id == wf.id
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.secondary.opacity(0.1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    // Frequency
                    sliderDetailCard(
                        title: "Frequency",
                        value: channel.frequency,
                        unit: "Hz",
                        range: 1...50,
                        step: 1,
                        color: .orange,
                        onChange: { v in isA ? controlVM.updateChannelA { $0.frequency = v } : controlVM.updateChannelB { $0.frequency = v } }
                    )

                    // Pulse Width
                    sliderDetailCard(
                        title: "Pulse Width",
                        value: Double(channel.pulseWidth),
                        unit: "μs",
                        range: 50...1000,
                        step: 10,
                        color: .pink,
                        onChange: { v in isA ? controlVM.updateChannelA { $0.pulseWidth = Int(v) } : controlVM.updateChannelB { $0.pulseWidth = Int(v) } }
                    )

                    // Phase Offset
                    sliderDetailCard(
                        title: "Phase Offset",
                        value: channel.phaseOffset,
                        unit: "°",
                        range: 0...360,
                        step: 5,
                        color: .teal,
                        onChange: { v in isA ? controlVM.updateChannelA { $0.phaseOffset = v } : controlVM.updateChannelB { $0.phaseOffset = v } }
                    )

                    // Duration
                    detailCard("Duration") {
                        Picker("", selection: Binding(
                            get: { channel.durationMs },
                            set: { v in isA ? controlVM.updateChannelA { $0.durationMs = v } : controlVM.updateChannelB { $0.durationMs = v } }
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

                    // Invert
                    Toggle("Invert Output", isOn: Binding(
                        get: { channel.isInverted },
                        set: { v in isA ? controlVM.updateChannelA { $0.isInverted = v } : controlVM.updateChannelB { $0.isInverted = v } }
                    ))
                    .padding()
                    .glassCard()
                }
                .padding()
            }
            .navigationTitle("Channel \(channel.id.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func detailCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            content()
        }
        .padding()
        .glassCard()
    }

    private func sliderDetailCard(
        title: String,
        value: Double,
        unit: String,
        range: ClosedRange<Double>,
        step: Double,
        color: Color,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        detailCard(title) {
            VStack {
                HStack {
                    Slider(value: .constant(value), in: range, step: step) { _ in }
                        .tint(color)
                    Text("\(Int(value))\(unit)")
                        .foregroundColor(.secondary)
                        .frame(width: 50)
                        .monospacedDigit()
                }
            }
        }
    }
}
