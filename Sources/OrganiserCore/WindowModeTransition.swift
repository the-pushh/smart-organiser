import Foundation

/// Coordinates asynchronous macOS full-screen transitions before window geometry is changed.
@MainActor
public enum WindowModeTransition {
    public static func setFullScreen(_ desired: Bool, read: () -> Bool?, write: (Bool) throws -> Void,
                                     pause: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws {
        try Task.checkCancellation()
        guard let current = read() else {
            if desired { throw PlanError.invalid("This app does not expose its full-screen state.") }
            return // Windows without full-screen support can still be arranged normally.
        }
        guard current != desired else { return }
        try write(desired)
        for _ in 0..<40 {
            try Task.checkCancellation()
            try await pause(.milliseconds(200))
            if read() == desired {
                // AXFullScreen can change before the Space animation has finished.
                try await pause(.milliseconds(800))
                try Task.checkCancellation()
                if read() == desired { return }
            }
        }
        throw PlanError.invalid(desired
            ? "The app did not finish restoring full-screen mode."
            : "The app did not finish leaving full-screen mode, so its window was not moved.")
    }
}
