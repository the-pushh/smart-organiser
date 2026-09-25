import Foundation

public enum WebPage {
    public static func validatedURL(_ text: String) throws -> URL {
        guard text.count <= 4096, !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              let url = parts.url else {
            throw PlanError.invalid("The plan contains an invalid web address. No windows were changed.")
        }
        return url
    }
}
