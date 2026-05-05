import SwiftUI

@main
struct YCYEStimApp: App {
    @StateObject private var controlVM = ControlVM()
    @StateObject private var settingsVM = SettingsVM()
    @StateObject private var deviceVM = DeviceVM()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controlVM)
                .environmentObject(settingsVM)
                .environmentObject(deviceVM)
                .glassBackgroundEffect(displayStyle: .automatic)
        }
    }
}
