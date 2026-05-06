import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)

                Text(bpmText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()

                Text(workoutManager.status.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Text(elapsedText)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)

            Button {
                if workoutManager.status == .running {
                    workoutManager.stopWorkout()
                } else {
                    Task { await workoutManager.startWorkout() }
                }
            } label: {
                Label(workoutManager.status == .running ? "Stop" : "Start", systemImage: workoutManager.status == .running ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(workoutManager.status == .running ? .red : .green)

            Button(role: .destructive) {
                workoutManager.sendEmergencyStop()
            } label: {
                Label("Emergency Stop", systemImage: "exclamationmark.octagon.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }

    private var bpmText: String {
        guard let bpm = workoutManager.latestBPM else { return "-- BPM" }
        return "\(Int(bpm)) BPM"
    }

    private var elapsedText: String {
        let minutes = workoutManager.elapsedSeconds / 60
        let seconds = workoutManager.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
