import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var presetStore = PresetStore()
    @StateObject private var deviceVM = DeviceVM()
    @EnvironmentObject var controlVM: ControlVM
    @EnvironmentObject var settingsVM: SettingsVM
    @AppStorage("ycy.onboardingDone") private var onboardingDone = false

    var body: some View {
        NavigationStack {
            TabView {
                ControlDashboardView()
                    .tabItem { Label("Control", systemImage: "bolt.fill") }

                PresetBrowserView()
                    .environmentObject(presetStore)
                    .tabItem { Label("Presets", systemImage: "square.stack.fill") }

                ProgramEditorView()
                    .environmentObject(presetStore)
                    .tabItem { Label("Programs", systemImage: "timeline.selection") }

                SessionHistoryView()
                    .environmentObject(presetStore)
                    .tabItem { Label("History", systemImage: "clock.fill") }

                SettingsView()
                    .environmentObject(deviceVM)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .tint(Color(hex: settingsVM.appearanceConfig.accentColor))
        }
        .onAppear {
            controlVM.injectSettings(settingsVM)
            controlVM.prepareHaptics()
            controlVM.updateWaveformPreview()
        }
        .fullScreenCover(isPresented: $onboardingDone.not) {
            OnboardingView { onboardingDone = true }
        }
        .fullScreenCover(isPresented: sessionActiveBinding) {
            SessionLiveView()
                .environmentObject(presetStore)
        }
    }

    /// Immediately show fullScreenCover when session starts, don't wait for async connect
    private var sessionActiveBinding: Binding<Bool> {
        Binding(
            get: {
                if case .active = controlVM.sessionState { return true }
                if case .starting = controlVM.sessionState { return true }
                if case .stopping = controlVM.sessionState { return true }
                return false
            },
            set: { _ in }
        )
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
            VStack(spacing: 40) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { i in
                        VStack(spacing: 24) {
                            Image(systemName: pages[i].icon).font(.system(size: 60)).foregroundColor(.accentColor)
                            Text(pages[i].title).font(.title.bold())
                            Text(pages[i].subtitle).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                        }.tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

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
