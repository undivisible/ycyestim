import SwiftUI

// MARK: - Session History View

struct SessionHistoryView: View {
    @EnvironmentObject var presetStore: PresetStore
    @State private var showConfirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if presetStore.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock.fill",
                        description: Text("Your session history will appear here after your first session.")
                    )
                } else {
                    List {
                        // Stats summary
                        statsSection

                        // Session list
                        ForEach(presetStore.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Session History")
            .toolbar {
                if !presetStore.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showConfirmClear = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .alert("Clear All Sessions?", isPresented: $showConfirmClear) {
                Button("Clear", role: .destructive) {
                    presetStore.deleteAllSessions()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var statsSection: some View {
        let totalSessions = presetStore.sessions.count
        let totalDuration = presetStore.sessions.reduce(0) { $0 + $1.durationMs }
        let avgStrength = presetStore.sessions.map { $0.maxStrengthReached }.reduce(0, +) / max(1, Double(totalSessions))

        return Section("Summary") {
            HStack(spacing: 16) {
                statCard("Sessions", "\(totalSessions)", "square.stack.fill")
                statCard("Total Time", formatDuration(totalDuration), "clock.fill")
                statCard("Avg Peak", "\(Int(avgStrength))%", "bolt.fill")
            }
        }
    }

    private func statCard(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                Text(session.formattedDuration)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(Int(session.maxStrengthReached))%", systemImage: "bolt.fill")
                    .font(.caption)
                Label(session.mode.rawValue, systemImage: session.mode.icon)
                    .font(.caption)

                if !session.presetsUsed.isEmpty {
                    Label(session.presetsUsed.joined(separator: ", "), systemImage: "square.stack.fill")
                        .font(.caption)
                }
            }

            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalMin = ms / 60_000
        if totalMin >= 60 {
            return String(format: "%dh %dm", totalMin / 60, totalMin % 60)
        }
        return "\(totalMin)m"
    }
}
