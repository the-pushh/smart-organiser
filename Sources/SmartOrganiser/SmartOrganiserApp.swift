import AppKit
import SwiftUI
import Carbon

@main
struct SmartOrganiserApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = LauncherDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class LauncherPanel: NSPanel {
    static func makeForPrompt() -> LauncherPanel {
        LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 72),
            styleMask: [.borderless], backing: .buffered, defer: false)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    private let model = OrganiserModel()
    private let inputFocus = PromptInputFocus()
    private var previousApplication: NSRunningApplication?
    private let onboarding = OnboardingState()
    private var showingOnboarding = false
    private var waitingForPermission = false
    private var shortcutAvailable = true
    private var panel: LauncherPanel!
    private var item: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Standard editing shortcuts still work in a background utility's text field.
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                       ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        panel = LauncherPanel.makeForPrompt()
        panel.title = "Smart Organiser"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        configurePrompt()
        model.didSubmit = { [weak self] in self?.dismiss() }
        model.didFinish = { [weak self] in self?.dismiss() }
        onboarding.permissionDidBecomeGranted = { [weak self] in
            guard let self, self.waitingForPermission else { return }
            self.waitingForPermission = false
            self.show()
        }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Smart Organiser")
        let menu = NSMenu()
        let summon = NSMenuItem(title: "What are you planning to do?   ⌃⌥Space", action: #selector(show), keyEquivalent: "")
        summon.target = self; menu.addItem(summon)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Organiser", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        item.menu = menu

        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<LauncherDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.toggle() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x4F524752, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        shortcutAvailable = result == noErr
        if !shortcutAvailable {
            model.error = "⌃⌥Space is already in use. Open this panel from the menu-bar icon."
        }
        onboarding.refreshPermission()
        if onboarding.needed || !shortcutAvailable { show() }
        // After onboarding, launch silently with only the menu-bar item.
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(); return true
    }
    private func configurePrompt() {
        // Detach the full-display host before sizing the compact prompt.
        panel.contentView = nil
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.setContentSize(NSSize(width: 720, height: 72))
        panel.contentView = NSHostingView(rootView: SummonView(model: model, focus: inputFocus, dismiss: { [weak self] in self?.dismiss() }))
        showingOnboarding = false
    }
    private func completeOnboarding() {
        onboarding.finish()
        dismiss()
        configurePrompt()
    }
    private func enableOnboardingPermission() {
        onboarding.refreshPermission()
        guard onboarding.permission.shouldOfferEnable else { return }
        // Let System Settings take the screen; the overlay returns once access is granted.
        waitingForPermission = true
        panel.orderOut(nil)
        onboarding.requestPermission()
    }
    @objc func show() {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != getpid() {
            previousApplication = frontmost
        }
        if onboarding.completed && showingOnboarding { configurePrompt() }
        if !onboarding.completed { onboarding.refreshPermission() }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if onboarding.needed && !showingOnboarding {
            onboarding.refreshPermission()
            showingOnboarding = true
            panel.hasShadow = false
            panel.isMovableByWindowBackground = false
            if let frame = screen?.frame { panel.setFrame(frame, display: false) }
            panel.contentView = NSHostingView(rootView: OnboardingView(state: onboarding,
                shortcutAvailable: shortcutAvailable,
                complete: { [weak self] in self?.completeOnboarding() },
                enablePermission: { [weak self] in self?.enableOnboardingPermission() },
                dismiss: { [weak self] in self?.dismiss() }))
        }
        if showingOnboarding {
            if let frame = screen?.frame { panel.setFrame(frame, display: true) }
        } else if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2 + frame.height * 0.12))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        if !showingOnboarding { inputFocus.focus() }
        // Activation and SwiftUI hosting can finish on the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.showingOnboarding else { return }
            self.panel.makeKey()
            self.inputFocus.focus()
        }
    }
    func toggle() { panel.isVisible ? dismiss() : show() }
    func dismiss() {
        waitingForPermission = false
        let shouldRestoreFocus = NSApp.isActive
        panel.orderOut(nil)
        if shouldRestoreFocus { previousApplication?.activate(options: []) }
    }
    @objc func quitApp() { NSApp.terminate(nil) }
}
