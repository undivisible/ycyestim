import SwiftUI

@main
struct YCYEStimWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workoutManager)
        }
    }
}
