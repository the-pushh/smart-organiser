import Foundation
import OrganiserCore

struct Credentials {
    struct Key { let value: String; let source: String }
    static var fileURL: URL {
        // The build script places the app at <project>/dist/Smart Organiser.app.
        let bundledProject = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let workingProject = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for root in [bundledProject, workingProject] {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path),
               FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/SmartOrganiser").path) {
                return root.appendingPathComponent(".env")
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Smart Organiser/.env")
    }
    static func read() throws -> Key? {
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return Key(value: key, source: "Process environment")
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let contents: String
            do { contents = try String(contentsOf: fileURL, encoding: .utf8) }
            catch { throw PlanError.invalid("Could not read \(fileURL.path). Check the file permissions and UTF-8 encoding.") }
            if let key = EnvironmentFile.value("OPENROUTER_API_KEY", in: contents) {
                return Key(value: key, source: ".env file")
            }
        }
        return nil
    }
}
