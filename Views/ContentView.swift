import SwiftUI
import UIKit

enum MainTab: String, CaseIterable, Identifiable {
    case control = "Control"
    case programs = "Programs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .control: return "bolt.fill"
        case .programs: return "timeline.selection"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var presetStore = PresetStore()
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var settingsVM: SettingsVM
    @EnvironmentObject var deviceVM: DeviceVM
    @AppStorage("ycy.onboardingDone") private var onboardingDone = false
    @State private var selectedTab: MainTab = .control
    @State private var showConnectionSetup = false

    var body: some View {
        tabbedContent
        .tint(Color(hex: settingsVM.appearanceConfig.accentColor))
        .onAppear {
            controlVM.injectSettings(settingsVM)
            controlVM.prepareHaptics()
            controlVM.updateWaveformPreview()
            autoConnectIfNeeded()
            Task { await controlVM.refreshHeartRateAuthorizationStatus() }
        }
        .fullScreenCover(isPresented: $onboardingDone.not) {
            OnboardingView { onboardingDone = true }
        }
        .sheet(isPresented: $showConnectionSetup) {
            ConnectionSetupView()
        }
    }

    @ViewBuilder
    private var tabbedContent: some View {
        if #available(iOS 26.0, *) {
            mainTabs
                .tabViewBottomAccessory {
                    bottomAccessory
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            mainTabs
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    fallbackAccessory
                }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ControlDashboardView()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(MainTab.control.rawValue, systemImage: MainTab.control.icon) }
            .tag(MainTab.control)

            ProgramEditorView()
                .environmentObject(presetStore)
                .tabItem { Label(MainTab.programs.rawValue, systemImage: MainTab.programs.icon) }
                .tag(MainTab.programs)

            SettingsView()
                .tabItem { Label(MainTab.settings.rawValue, systemImage: MainTab.settings.icon) }
                .tag(MainTab.settings)
        }
    }

    private var bottomAccessory: some View {
        sessionAccessory
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var fallbackAccessory: some View {
        sessionAccessory
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var sessionAccessory: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(sessionStateColor)
                .frame(width: 10, height: 10)
                .shadow(color: sessionStateColor.opacity(0.45), radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(sessionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sessionTime)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .lineLimit(1)
                    Text(sessionDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 6)
            primaryActionButton
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sessionTitle), \(sessionTime), \(sessionDetail)")
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: primaryAction) {
                primaryActionLabel
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(primaryActionColor)
            .disabled(connectionText == "Connecting")
        } else {
            Button(action: primaryAction) {
                primaryActionLabel
                    .foregroundColor(.white)
                    .background(primaryActionColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(connectionText == "Connecting")
        }
    }

    private var primaryActionLabel: some View {
        Label(primaryActionTitle, systemImage: primaryActionIcon)
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 92, height: 42)
            .accessibilityLabel(primaryActionTitle)
    }

    private func primaryAction() {
        guard connectionText == "Connected" else {
            notify(.warning)
            showConnectionSetup = true
            return
        }

        if controlVM.isSessionActive {
            notify(.warning)
            controlVM.stopSession()
        } else {
            notify(.success)
            controlVM.startSession()
        }
    }

    private var primaryActionTitle: String {
        switch connectionText {
        case "Connected":
            return controlVM.isSessionActive ? "Stop" : "Start"
        case "Connecting":
            return "Connecting"
        default:
            return "Connect"
        }
    }

    private var primaryActionIcon: String {
        switch connectionText {
        case "Connected":
            return controlVM.isSessionActive ? "stop.fill" : "play.fill"
        case "Connecting":
            return "antenna.radiowaves.left.and.right"
        default:
            return "wifi.slash"
        }
    }

    private var primaryActionColor: Color {
        switch connectionText {
        case "Connected":
            return controlVM.isSessionActive ? .orange : .green
        case "Connecting":
            return .orange
        case "Error":
            return .red
        default:
            return .accentColor
        }
    }

    private var sessionTitle: String {
        switch controlVM.sessionState {
        case .starting:
            return "Starting Session"
        case .active:
            return controlVM.isPaused ? "Paused Session" : "Live Session"
        case .stopping:
            return "Ending Session"
        case .emergencyStopped:
            return "Emergency Stop"
        case .idle:
            switch connectionText {
            case "Connected": return "Ready Session"
            case "Connecting": return "Connecting Device"
            case "Error": return "Connection Issue"
            default: return "No Device"
            }
        }
    }

    private var sessionTime: String {
        switch controlVM.sessionState {
        case .active, .starting, .stopping:
            return controlVM.sessionElapsedFormatted
        default:
            return "00:00"
        }
    }

    private var sessionDetail: String {
        var parts = [connectionText]
        if connectionText == "Connected" || controlVM.isSessionActive {
            parts.append("\(Int(controlVM.currentMaxStrength.rounded()))% max")
        }
        if let bpm = controlVM.heartRateDisplayBPM {
            parts.append("\(Int(bpm.rounded())) BPM")
        }
        return parts.joined(separator: " · ")
    }

    private var sessionStateColor: Color {
        switch controlVM.sessionState {
        case .active:
            return controlVM.isPaused ? .orange : .green
        case .starting, .stopping:
            return .orange
        case .emergencyStopped:
            return .red
        case .idle:
            switch connectionText {
            case "Connected": return .green
            case "Connecting": return .orange
            case "Error": return .red
            default: return .secondary
            }
        }
    }

    private var connectionText: String {
        switch deviceVM.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .error:
            return "Error"
        case .disconnected:
            switch controlVM.connectionStatus {
            case .connected: return "Connected"
            case .connecting: return "Connecting"
            case .error: return "Error"
            case .disconnected: return "Disconnected"
            }
        }
    }

    private func autoConnectIfNeeded() {
        guard settingsVM.connectionConfig.mode == .ble,
              settingsVM.connectionConfig.bleAutoConnect,
              let lastDeviceId = settingsVM.connectionConfig.bleLastDeviceId else { return }
        deviceVM.autoConnectLastDevice(id: lastDeviceId)
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    let onComplete: () -> Void

    let pages: [OnboardingPage] = [
        OnboardingPage(icon: "bolt.fill", title: "Dual Channel Control",
                       subtitle: "Independently control two channels with different waveforms, strengths, and timing. Or sync them together."),
        OnboardingPage(icon: "waveform", title: "Waveform Engine",
                       subtitle: "Choose from 11 built-in waveforms or draw your own. Adjust frequency, pulse width, and phase offset."),
        OnboardingPage(icon: "shield.fill", title: "Safety First",
                       subtitle: "Max strength limits, session timers, ramp-up protection, and emergency stop. Shake to stop all output."),
        OnboardingPage(icon: "play.circle.fill", title: "Presets & Programs",
                       subtitle: "Start with built-in presets or create your own. Build timed programs that automate complex sequences.")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { i in
                        VStack(spacing: 16) {
                            Image(systemName: pages[i].icon)
                                .font(.system(size: 46))
                                .foregroundColor(.accentColor)
                            Text(pages[i].title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text(pages[i].subtitle)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 12)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: 360)

                Button {
                    if currentPage < pages.count - 1 { withAnimation { currentPage += 1 } }
                    else { onComplete() }
                } label: {
                    Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor).foregroundColor(.white).clipShape(Capsule())
                }
                .padding(.horizontal, 40)
            }
            .padding(.vertical, 24)
        }
    }
}

struct OnboardingPage { let icon: String; let title: String; let subtitle: String }

// MARK: - Negated Binding helper

extension Binding where Value == Bool {
    var not: Binding<Bool> {
        Binding<Bool>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
