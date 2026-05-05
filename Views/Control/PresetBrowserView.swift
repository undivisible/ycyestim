import SwiftUI

// MARK: - Preset Browser View

struct PresetBrowserView: View {
    @EnvironmentObject var presetStore: PresetStore
    @EnvironmentObject var controlVM: ControlVM
    @State private var searchText: String = ""
    @State private var showEditor: Bool = false

    var filteredPresets: [Preset] {
        if searchText.isEmpty {
            return presetStore.presets
        }
        return presetStore.presets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                    ForEach(filteredPresets) { preset in
                        presetCard(preset)
                    }
                }
                .padding()
            }
            .navigationTitle("Presets")
            .searchable(text: $searchText, prompt: "Search presets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                WaveformEditorView { waveform in
                    // Create new preset from custom waveform
                    let newPreset = Preset(
                        name: waveform.name,
                        icon: "pencil",
                        color: "#BF5AF2",
                        channelA: .init(strength: 30, waveform: waveform, frequency: 20, pulseWidth: 200, phaseOffset: 0, durationMs: 0)
                    )
                    presetStore.savePreset(newPreset)
                }
            }
        }
    }

    private func presetCard(_ preset: Preset) -> some View {
        Button {
            controlVM.applyPreset(preset)
        } label: {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: preset.icon)
                        .font(.title)
                        .foregroundColor(Color(hex: preset.color))
                    Spacer()
                    if preset.isBuiltin {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(preset.name)
                    .font(.headline)
                    .lineLimit(1)

                // Channel info
                VStack(alignment: .leading, spacing: 4) {
                    Text("CH A: \(preset.channelA.waveform.name) · \(Int(preset.channelA.strength))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let b = preset.channelB {
                        Text("CH B: \(b.waveform.name) · \(Int(b.strength))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(hex: preset.color).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: preset.color).opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Quick Preset Sheet

struct QuickPresetSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var controlVM: ControlVM

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                    ForEach(Preset.allBuiltins) { preset in
                        Button {
                            controlVM.applyPreset(preset)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: preset.icon)
                                    .font(.title)
                                    .foregroundColor(Color(hex: preset.color))
                                Text(preset.name)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: preset.color).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Quick Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
