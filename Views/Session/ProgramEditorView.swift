import SwiftUI

// MARK: - Program Editor View

struct ProgramEditorView: View {
    @EnvironmentObject var presetStore: PresetStore
    @State private var selectedProgram: Program?
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                // Built-in programs
                Section("Built-in Programs") {
                    ForEach(Program.allBuiltins) { program in
                        NavigationLink(destination: ProgramDetailView(program: program)) {
                            programRow(program)
                        }
                    }
                }

                // Custom programs
                Section("My Programs") {
                    ForEach(presetStore.programs.filter { !Program.allBuiltins.map(\.id).contains($0.id) }) { program in
                        NavigationLink(destination: ProgramDetailView(program: program)) {
                            programRow(program)
                        }
                    }

                    Button {
                        showEditor = true
                    } label: {
                        Label("Create Program", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Programs")
            .sheet(isPresented: $showEditor) {
                CreateProgramView()
            }
        }
    }

    private func programRow(_ program: Program) -> some View {
        HStack {
            Image(systemName: program.icon)
                .foregroundColor(Color(hex: program.color))
                .font(.title2)

            VStack(alignment: .leading) {
                Text(program.name)
                    .font(.headline)
                Text("\(program.steps.count) steps · \(program.loopCount == 0 ? "∞ loops" : "\(program.loopCount) loops")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Program Detail View

struct ProgramDetailView: View {
    @EnvironmentObject var controlVM: ControlVM
    let program: Program
    @State private var isRunning: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Program info
                HStack {
                    Image(systemName: program.icon)
                        .font(.largeTitle)
                        .foregroundColor(Color(hex: program.color))
                    VStack(alignment: .leading) {
                        Text(program.name)
                            .font(.title2.bold())
                        Text("\(program.steps.count) steps · \(program.loopCount == 0 ? "Infinite" : "\(program.loopCount)") loops")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .glassCard()

                // Timeline
                VStack(alignment: .leading) {
                    Text("Timeline")
                        .font(.headline)

                    ForEach(program.steps) { step in
                        timelineStep(step)
                    }
                }
                .padding()
                .glassCard()

                // Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings")
                        .font(.headline)

                    LabeledContent("Auto Progress") {
                        Image(systemName: program.autoProgress ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(program.autoProgress ? .green : .secondary)
                    }

                    LabeledContent("Transition Smoothness") {
                        Text("\(Int(program.transitionSmoothness * 100))%")
                    }

                    LabeledContent("Pause Between Steps") {
                        Text("\(program.pauseBetweenSteps / 1000)s")
                    }
                }
                .padding()
                .glassCard()

                // Run button
                Button {
                    if isRunning {
                        controlVM.stopSession()
                        isRunning = false
                    } else {
                        controlVM.activeProgram = program
                        controlVM.startSession()
                        isRunning = true
                    }
                } label: {
                    Label(isRunning ? "Stop" : "Run Program", systemImage: isRunning ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isRunning ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding()
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timelineStep(_ step: Program.ProgramStep) -> some View {
        HStack {
            VStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 30)
            }

            VStack(alignment: .leading) {
                Text(formatTime(step.timeOffset))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("CH A: \(step.channelA.waveform.name) @ \(Int(step.channelA.strength))%")
                    .font(.subheadline)
            }
        }
    }

    private func formatTime(_ ms: Int) -> String {
        let sec = ms / 1000
        return String(format: "%02d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - Create Program View

struct CreateProgramView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var presetStore: PresetStore
    @State private var name: String = ""
    @State private var steps: [Program.ProgramStep] = []
    @State private var loopCount: Int = 0
    @State private var autoProgress: Bool = true
    @State private var smoothness: Double = 0.5

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Program name", text: $name)
                }

                Section("Steps") {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        VStack {
                            Text("Step \(index + 1) at \(formatTime(step.timeOffset))")
                                .font(.headline)
                            Text("CH A: \(step.channelA.waveform.name) @ \(Int(step.channelA.strength))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        let newStep = Program.ProgramStep(
                            timeOffset: steps.last.map { $0.timeOffset + 30_000 } ?? 0,
                            channelA: .init(strength: 20, waveform: .pulse(count: .single), frequency: 20, pulseWidth: 200, durationMs: 30_000)
                        )
                        steps.append(newStep)
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                }

                Section("Options") {
                    Stepper("Loops: \(loopCount == 0 ? "Infinite" : String(loopCount))", value: $loopCount, in: 0...10)
                    Toggle("Auto Progress", isOn: $autoProgress)
                    LabeledContent("Smoothness") {
                        Slider(value: $smoothness, in: 0...1)
                            .frame(width: 120)
                    }
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let program = Program(
                            name: name.isEmpty ? "Untitled" : name,
                            steps: steps,
                            loopCount: loopCount,
                            autoProgress: autoProgress,
                            transitionSmoothness: smoothness
                        )
                        presetStore.saveProgram(program)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func formatTime(_ ms: Int) -> String {
        let sec = ms / 1000
        return String(format: "%02d:%02d", sec / 60, sec % 60)
    }
}
