import AppKit
import ApplicationServices
import OrganiserCore

/// Check real cross-process access. A system-wide focused-app read may succeed
/// for our own focused panel even when TCC denies access to every other app.
enum AccessibilityAccess {
    static func probe(processID: pid_t, ownProcessID: pid_t = getpid(),
                      read: () -> AXError) -> AccessibilityPermission.Probe {
        guard processID != ownProcessID else { return .inconclusive }
        switch read() {
        case .success: return .accessible
        case .apiDisabled: return .accessDenied
        default: return .inconclusive
        }
    }

    static func check() -> AccessibilityPermission {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != getpid() && $0.activationPolicy == .regular && !$0.isTerminated
        }
        for app in candidates.prefix(3) {
            let result = probe(processID: app.processIdentifier) {
                let root = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.5)
                var windows: CFTypeRef?
                return AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
            }
            switch result {
            case .accessible: return .granted
            case .accessDenied: return .denied
            case .inconclusive: continue
            }
        }
        return .resolve(trusted: trusted, probe: .inconclusive)
    }
}
