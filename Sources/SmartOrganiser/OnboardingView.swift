import SwiftUI
import AppKit
import ApplicationServices
import OrganiserCore

@MainActor
final class OnboardingState: ObservableObject {
    static let completionKey = "onboardingCompleted.v1"
    @Published private(set) var permission: AccessibilityPermission = .checking
    var permissionGranted: Bool { permission == .granted }
    var permissionDidBecomeGranted: (() -> Void)?
    private var arrivalSound: NSSound?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var completed: Bool { defaults.bool(forKey: Self.completionKey) }
    // Completion is permanent. Runtime permission recovery belongs to the task flow.
    var needed: Bool { !completed }

    func refreshPermission() {
        let result = AccessibilityAccess.check()
        let newlyGranted = result == .granted && permission != .granted
        permission = result
        if newlyGranted { permissionDidBecomeGranted?() }
    }
    func requestPermission() {
        refreshPermission()
        guard permission.shouldOfferEnable else { return }
        WindowController().requestPermission()
    }
    func playArrivalSound() {
        arrivalSound = NSSound(named: NSSound.Name("Glass"))
        arrivalSound?.volume = 0.22
        arrivalSound?.play()
    }
    func finish() {
        // Let’s begin is offered after a successful check. Do not undo the user's completion
        // if a subsequent permission probe is temporarily inconclusive.
        defaults.set(true, forKey: Self.completionKey)
    }
}

/// A native backdrop blur, fading to completely clear around the screen edges.
private struct FrostedBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    let shortcutAvailable: Bool
    let complete: () -> Void
    let enablePermission: () -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var illuminated = false
    @State private var showShortcut = false
    @State private var showPermission = false
    private let accent = Color(red: 0.68, green: 0.9, blue: 0.74)

    var body: some View {
        GeometryReader { geometry in
            let radius = max(420, min(geometry.size.width, geometry.size.height) * 0.68)
            ZStack {
                FrostedBackdrop()
                    .mask(RadialGradient(stops: [.init(color: .black, location: 0),
                        .init(color: .black.opacity(0.97), location: 0.40),
                        .init(color: .clear, location: 1)], center: .center, startRadius: 0, endRadius: radius))
                RadialGradient(colors: [Color(red: 0.035, green: 0.065, blue: 0.05).opacity(0.8), .clear],
                    center: .center, startRadius: 70, endRadius: radius)
                VStack(spacing: 30) {
                    ZStack {
                        Circle().fill(accent.opacity(illuminated ? 0.18 : 0))
                            .frame(width: 180, height: 180).blur(radius: 45)
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 70, weight: .light))
                            .foregroundStyle(accent)
                            .shadow(color: accent.opacity(illuminated ? 0.75 : 0), radius: 27)
                            .scaleEffect(illuminated || reduceMotion ? 1 : 0.88)
                            .opacity(illuminated ? 1 : 0)
                    }.frame(height: 150).accessibilityLabel("Organiser logo")
                    VStack(spacing: 11) {
                        Text("Make room for what’s next.")
                            .font(.system(size: 32, weight: .medium, design: .serif))
                        Text("Your workspace, a shortcut away.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                    }.opacity(illuminated ? 1 : 0)
                    VStack(spacing: 13) {
                        HStack(spacing: 12) {
                            Text("⌃"); Text("⌥"); Text("space").font(.system(size: 22, weight: .medium, design: .monospaced))
                        }.font(.system(size: 30, weight: .light, design: .monospaced))
                            .foregroundStyle(accent)
                            .accessibilityElement(children: .ignore).accessibilityLabel("Control Option Space")
                        Text(shortcutAvailable ? "Summon Organiser from anywhere. Tell me your plan. Set the vibe." : "Shortcut in use. You can summon Organiser from the menu bar.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    }
                    .opacity(showShortcut ? 1 : 0)
                    .offset(y: showShortcut || reduceMotion ? 0 : 8)
                    .accessibilityHidden(!showShortcut)
                    VStack(spacing: 16) {
                        if state.permissionGranted {
                            Label("Accessibility enabled", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
                            Text("You’re ready. I’ll be in your menu bar.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                            Button("Let’s begin") { complete() }.buttonStyle(PrimaryActionStyle())
                                .keyboardShortcut(.return, modifiers: [])
                        } else if state.permission.shouldOfferEnable {
                            Text("One permission to move your windows.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                            Button("Enable Accessibility") {
                                state.refreshPermission()
                                if !state.permissionGranted { enablePermission() }
                            }.buttonStyle(PrimaryActionStyle())
                            Text("Enable Smart Organiser in System Settings. I’ll notice when it’s ready.")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        } else if state.permission == .checking {
                            ProgressView().controlSize(.small)
                            Text("Checking Accessibility…").font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            Text("Couldn’t verify Accessibility yet.").font(.system(size: 13)).foregroundStyle(.secondary)
                            Button("Check again") { state.refreshPermission() }.buttonStyle(PrimaryActionStyle())
                        }
                    }
                    .frame(height: 115)
                    .opacity(showPermission ? 1 : 0)
                    .offset(y: showPermission || reduceMotion ? 0 : 8)
                    .allowsHitTesting(showPermission)
                    .disabled(!showPermission)
                    .accessibilityHidden(!showPermission)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: dismiss) {
                            Label("esc", systemImage: "xmark").font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7)).padding(12)
                                .background(.black.opacity(0.2), in: Capsule())
                        }.buttonStyle(.plain).help("Finish setup later")
                    }
                    Spacer()
                }.padding(30)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onExitCommand { dismiss() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in state.refreshPermission() }
        .task {
            // Check before revealing any permission controls, even if already authorized at launch.
            state.refreshPermission()
            state.playArrivalSound()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.5)) { illuminated = true }
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 1700))
                withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.8)) { showShortcut = true }
                try await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 1500))
                state.refreshPermission()
                withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.8)) { showPermission = true }
                while !Task.isCancelled {
                    state.refreshPermission()
                    try await Task.sleep(for: .milliseconds(700))
                }
            } catch { return }
        }
    }
}
