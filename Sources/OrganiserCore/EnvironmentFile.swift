import Foundation

public enum EnvironmentFile {
    /// Literal dotenv values only. No shell evaluation, interpolation, or multiline secrets.
    public static func value(_ name: String, in contents: String) -> String? {
        var result: String?
        for raw in contents.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "="),
                  line[..<separator].trimmingCharacters(in: .whitespaces) == name else { continue }
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                let rest = value.dropFirst()
                guard let end = rest.firstIndex(of: quote) else { continue }
                let tail = rest[rest.index(after: end)...].trimmingCharacters(in: .whitespaces)
                guard tail.isEmpty || tail.hasPrefix("#") else { continue }
                value = String(rest[..<end])
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            result = value.isEmpty ? nil : value
        }
        return result
    }
}
