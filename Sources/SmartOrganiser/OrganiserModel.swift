import AppKit
import SwiftUI
import OrganiserCore

@MainActor
final class OrganiserModel: ObservableObject {
    @Published var taskText = ""
    @Published var vibeEnabled = false
    @Published var busy = false
    @Published var status = "⌃⌥Space to summon · Return to arrange"
    @Published var error: String?
    var didSubmit: (() -> Void)?
    var didFinish: (() -> Void)?
    private let controller = WindowController()
    private var operation: Task<Void, Never>?

    func generate() {
        guard !busy else { return }
        let text = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        didSubmit?()
        error = nil
        guard controller.hasPermission else {
            controller.requestPermission()
            error = "Enable Organiser in macOS Accessibility, then press Return again."
            return
        }
        let key: String
        do {
            guard let stored = try Credentials.read() else {
                error = "OPENROUTER_API_KEY is missing from .env."
                return
            }
            key = stored.value
        } catch { self.error = error.localizedDescription; return }
        let captured: Workspace
        do { captured = try controller.scan() }
        catch { self.error = error.localizedDescription; return }
        let request: WorkspaceRequest
        do {
            request = try WorkspaceRequest.make(task: text, setVibe: vibeEnabled, workspace: captured)
        } catch { self.error = error.localizedDescription; return }
        busy = true
        status = "Making room for your next thing…"
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                let generated = try await Planner().plan(task: request.prompt, workspace: captured, key: key)
                try request.validateMusic(in: generated, workspace: captured)
                try Task.checkCancellation()
                let failures = try await controller.reset(generated, snapshot: captured) { self.status = $0 }
                if failures.isEmpty {
                    status = "Everything’s set up. Now do the thing."
                    try await Task.sleep(for: .milliseconds(700))
                    didFinish?()
                } else {
                    status = "Some windows need attention."
                    error = failures.joined(separator: "\n")
                }
            } catch is CancellationError { status = "Stopped. Windows already closed cannot be restored." }
            catch { self.error = error.localizedDescription; status = "Couldn’t finish the arrangement." }
        }
    }
    func cancel() { operation?.cancel() }
}
