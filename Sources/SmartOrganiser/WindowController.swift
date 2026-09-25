import AppKit
import ApplicationServices
import OrganiserCore

@MainActor
final class WindowController {
    struct Captured {
        var info: WindowInfo
        var element: AXUIElement
    }
    private(set) var captured: [String: Captured] = [:]
    var hasPermission: Bool { AccessibilityAccess.check() == .granted }

    func requestPermission() {
        guard AccessibilityAccess.check().shouldOfferEnable else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    func frame(_ element: AXUIElement) -> Rect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero; var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p),
              AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return Rect(x: p.x, y: p.y, width: s.width, height: s.height)
    }
    func displays() -> [Display] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        func convert(_ r: NSRect) -> Rect { Rect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
        return NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
            return Display(id: id, name: screen.localizedName, frame: convert(screen.frame), visibleFrame: convert(screen.visibleFrame))
        }
    }
    func installedApps() -> [AppInfo] {
        var apps: [String: AppInfo] = [:]
        // Discover URL-capable browsers from macOS, not a hard-coded browser list.
        // This is a local capability query, not a page to open or a network request.
        let browsers = Set(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.invalid")!)
            .compactMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() })
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            while let url = walker.nextObject() as? URL {
                if url.pathExtension == "app" {
                    walker.skipDescendants()
                    if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier {
                        apps[id] = AppInfo(id: id, name: (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                            ?? url.deletingPathExtension().lastPathComponent, supportsWebURLs: browsers.contains(id.lowercased()))
                    }
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            if let id = app.bundleIdentifier { apps[id] = AppInfo(id: id, name: app.localizedName ?? id, supportsWebURLs: browsers.contains(id.lowercased())) }
        }
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func applicationWindows(_ root: AXUIElement) throws -> [AXUIElement] {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw)
        if result == .apiDisabled {
            throw PlanError.invalid("macOS denied Accessibility access. Refresh Smart Organiser’s existing entry in System Settings → Privacy & Security → Accessibility, then relaunch Organiser.")
        }
        // An app without a window interface is not a failed Accessibility connection.
        if result == .attributeUnsupported || result == .noValue { return [] }
        try check(result, "Reading app windows")
        return raw as? [AXUIElement] ?? []
    }
    func scan() throws -> Workspace {
        let previous = captured
        captured = [:]
        guard hasPermission else {
            throw PlanError.invalid("macOS denied Accessibility access to other apps. Refresh Smart Organiser’s existing Accessibility entry, then relaunch it.")
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            guard let appID = app.bundleIdentifier else { continue }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.5)
            let windows = try applicationWindows(root)
            for element in windows {
                guard (value(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      let rect = frame(element) else { continue }
                let old = previous.values.first { CFEqual($0.element, element) }
                let id = old?.info.id ?? UUID().uuidString
                let info = WindowInfo(id: id, appID: appID, appName: app.localizedName ?? appID,
                    title: value(element, kAXTitleAttribute) as? String ?? "Untitled",
                    frame: rect, minimized: value(element, kAXMinimizedAttribute) as? Bool ?? false)
                captured[id] = Captured(info: info, element: element)
            }
        }
        return Workspace(displays: displays(), apps: installedApps(), windows: captured.values.map(\.info).sorted { $0.appName < $1.appName },
            projectDirectory: FileManager.default.fileExists(atPath: Credentials.fileURL.deletingLastPathComponent().appendingPathComponent("Package.swift").path)
                ? Credentials.fileURL.deletingLastPathComponent().path : nil)
    }
    private func check(_ error: AXError, _ operation: String) throws {
        if error != .success { throw PlanError.invalid("\(operation) was refused by the app (\(error.rawValue)).") }
    }
    private func minimize(_ window: AXUIElement, _ flag: Bool) throws {
        try check(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, flag ? kCFBooleanTrue : kCFBooleanFalse), "Minimizing/restoring")
    }
    private func fullScreen(_ window: AXUIElement, _ desired: Bool) async throws {
        try await WindowModeTransition.setFullScreen(desired,
            read: { self.value(window, "AXFullScreen") as? Bool },
            write: { desired in
                let result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString,
                    desired ? kCFBooleanTrue : kCFBooleanFalse)
                if result != .success {
                    // Some apps expose only the native green-window-button action.
                    if self.value(window, "AXFullScreen") as? Bool == desired { return }
                    if let button = self.value(window, kAXFullScreenButtonAttribute),
                       CFGetTypeID(button) == AXUIElementGetTypeID(),
                       AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success { return }
                    throw PlanError.invalid("The app refused to change full-screen mode (\(result.rawValue)).")
                }
            })
    }
    private func move(_ window: AXUIElement, to rect: Rect) async throws {
        try await fullScreen(window, false)
        try minimize(window, false)
        var pid: pid_t = 0
        try check(AXUIElementGetPid(window, &pid), "Finding window owner")
        let owner = AXUIElementCreateApplication(pid)
        // Enhanced UI animates AX geometry writes; overlapping animations can
        // restore the old frame. Suspend it only for this placement and restore it
        // on every exit, including cancellation, for assistive clients.
        let enhancedUI = value(owner, "AXEnhancedUserInterface") as? Bool == true
        if enhancedUI {
            _ = AXUIElementSetAttributeValue(owner, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        defer {
            if enhancedUI {
                _ = AXUIElementSetAttributeValue(owner, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
        var point = CGPoint(x: rect.x, y: rect.y)
        var size = CGSize(width: rect.width, height: rect.height)
        // Retry through app layout/Space animation settling, and verify actual geometry.
        var lastError: Error?
        for _ in 0..<6 {
            try Task.checkCancellation()
            do {
                try check(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!), "Moving")
                try check(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!), "Resizing")
                try check(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!), "Positioning")
                lastError = nil
            } catch { lastError = error }
            try await Task.sleep(for: .milliseconds(200))
            if let actual = frame(window), abs(actual.x - rect.x) < 24, abs(actual.y - rect.y) < 24,
               abs(actual.width - rect.width) < 24, abs(actual.height - rect.height) < 24 { return }
        }
        if let lastError { throw lastError }
        throw PlanError.invalid("The app constrained its window size or position; the requested layout was only partly applied.")
    }

    /// Verifies existence by asking the owning app, not by reading potentially cached geometry.
    private func isOpen(_ window: Captured) throws -> Bool {
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(window.element, &pid)
        if pidResult == .invalidUIElement { return false }
        guard pidResult == .success else {
            throw PlanError.invalid("Couldn’t verify \(window.info.appName)’s window. This app will be left alone.")
        }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.5)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &result)
        guard error == .success, let windows = result as? [AXUIElement] else {
            throw PlanError.invalid("Couldn’t verify whether \(window.info.appName)’s window closed. This app will be left alone.")
        }
        return windows.contains { CFEqual($0, window.element) }
    }
    static func isBlockingDialog(role: String?, subrole: String?, modal: Bool) -> Bool {
        role == kAXSheetRole || (role == kAXWindowRole && subrole != kAXStandardWindowSubrole &&
            modal)
    }
    private func hasSavePrompt(_ window: AXUIElement) -> Bool {
        func isDialog(_ element: AXUIElement, depth: Int) -> Bool {
            let role = value(element, kAXRoleAttribute) as? String
            let subrole = value(element, kAXSubroleAttribute) as? String
            // Electron can mark ordinary web content as modal; only native
            // sheets or nonstandard dialog windows block closure.
            if Self.isBlockingDialog(role: role, subrole: subrole,
                modal: value(element, "AXModal") as? Bool == true) { return true }
            guard depth < 2 else { return false }
            return (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains { isDialog($0, depth: depth + 1) }
        }
        if isDialog(window, depth: 0) { return true }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return false }
        let root = AXUIElementCreateApplication(pid)
        // Some confirmations are separate app-modal windows, not attached sheets.
        return (value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).contains { isDialog($0, depth: 0) }
    }
    private func closeForReset(_ window: Captured) async throws {
        guard try isOpen(window) else { return }
        guard !hasSavePrompt(window.element) else {
            throw PlanError.invalid("Finish the open dialog in \(window.info.appName), when convenient. Other apps will still be set up.")
        }
        // Music can acknowledge its hidden full-screen close button without closing.
        // Leave the Space ourselves, then fetch the visible window's close control.
        try await fullScreen(window.element, false)
        guard try isOpen(window) else { return }
        guard let button = value(window.element, kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() else {
            throw PlanError.invalid("\(window.info.appName) did not expose a close button. This app will be left alone.")
        }
        // Close only after the full-screen transition has settled.
        try check(AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString), "Closing \(window.info.appName)")
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(150))
            if try !isOpen(window) { return }
            if hasSavePrompt(window.element) {
                throw PlanError.invalid("\(window.info.appName) needs a save decision. Resolve its dialog, when convenient. Other apps will still be set up.")
            }
        }
        throw PlanError.invalid("\(window.info.appName)’s window is still open. Finish any save or close prompt there, when convenient. Other apps will still be set up.")
    }
    /// Invoke the app's actual native New command; never type into an existing document.
    private func createDocument(in root: AXUIElement) async throws {
        func findNew(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 5 else { return nil }
            if (value(element, "AXMenuItemCmdChar") as? String)?.lowercased() == "n",
               (value(element, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue == 0,
               value(element, kAXEnabledAttribute) as? Bool == true { return element }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = findNew(child, depth: depth + 1) { return found }
            }
            return nil
        }
        for _ in 0..<20 {
            try Task.checkCancellation()
            if let menu = value(root, kAXMenuBarAttribute), CFGetTypeID(menu) == AXUIElementGetTypeID(),
               let command = findNew(menu as! AXUIElement, depth: 0) {
                try check(AXUIElementPerformAction(command, kAXPressAction as CFString), "Creating a new document")
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw PlanError.invalid("The app opened, but its native New command is unavailable.")
    }
    private func openFresh(_ action: LayoutAction, progress: (String) -> Void) async throws {
        guard let id = action.appID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            throw PlanError.invalid("The selected app is no longer installed.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app: NSRunningApplication
        if let pages = action.urls, !pages.isEmpty {
            let webURLs = try pages.map(WebPage.validatedURL)
            progress("Opening relevant web pages…")
            app = try await NSWorkspace.shared.open(webURLs, withApplicationAt: url, configuration: configuration)
        } else if let project = action.projectPath {
            app = try await NSWorkspace.shared.open([URL(fileURLWithPath: project, isDirectory: true)],
                withApplicationAt: url, configuration: configuration)
        } else {
            app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        var preparationError: Error?
        if action.createNewDocument == true {
            do { try await createDocument(in: root) }
            catch is CancellationError { throw CancellationError() }
            catch { preparationError = error }
        }
        var newWindows: [AXUIElement] = []
        var stablePolls = 0
        var lastReadError: Error?

        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(200))
            do {
                let windows = try applicationWindows(root).filter {
                    (value($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole
                }
                let same = windows.count == newWindows.count && windows.allSatisfy { candidate in
                    newWindows.contains { CFEqual(candidate, $0) }
                }
                stablePolls = same && !windows.isEmpty ? stablePolls + 1 : 0
                newWindows = windows
                lastReadError = nil
            } catch {
                if !hasPermission { throw error }
                lastReadError = error
            }
            if !newWindows.isEmpty && stablePolls >= (action.urls == nil ? 5 : 10) { break }
        }
        guard !newWindows.isEmpty else {
            if let lastReadError { throw lastReadError }
            throw PlanError.invalid("The app opened without a window. It may need you to create or choose a document.")
        }
        // Normalize every restored window before computing placement.
        for window in newWindows { try await fullScreen(window, false) }
        guard let screen = displays().first(where: { $0.id == action.displayID }), let rect = action.rect else {
            throw PlanError.invalid("The selected display is no longer connected.")
        }
        _ = app.unhide()
        progress("Placing \(app.localizedName ?? id)…")
        let tiles = WindowTiles.rectangles(count: newWindows.count, in: rect.placed(in: screen.visibleFrame))
        var placementErrors: [String] = preparationError.map { [$0.localizedDescription] } ?? []
        for (window, tile) in zip(newWindows, tiles) {
            try Task.checkCancellation()
            do { try await move(window, to: tile) }
            catch is CancellationError { throw CancellationError() }
            catch { placementErrors.append(error.localizedDescription) }
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        if !placementErrors.isEmpty { throw PlanError.invalid(placementErrors.joined(separator: "\n")) }
    }
    func reset(_ plan: LayoutPlan, snapshot: Workspace, progress: (String) -> Void) async throws -> [String] {
        guard hasPermission else { throw PlanError.invalid("Accessibility access is needed to set up the workspace.") }
        let live = try scan()
        guard live.displays == snapshot.displays else { throw PlanError.invalid("Displays changed. Submit the task again.") }
        // Copy references before mutating windows. The planner cannot choose which existing windows to close.
        let closing = captured
        return try await WorkspaceReset.run(plan: plan, workspace: live, closeWindow: { info in
            progress("Closing \(info.appName)…")
            guard let window = closing[info.id] else { throw PlanError.invalid("The window inventory changed. This app will be left alone.") }
            try await self.closeForReset(window)
        }, openApp: { action in
            let name = live.apps.first { $0.id == action.appID }?.name ?? "app"
            progress("Opening \(name)…")
            try await self.openFresh(action, progress: progress)
        })
    }
}
