import Foundation

public enum AccessibilityPermission: Equatable, Sendable {
    case checking, granted, denied, unavailable

    public var shouldOfferEnable: Bool { self == .denied }

    public enum Probe: Sendable { case accessible, accessDenied, inconclusive }
    public static func resolve(trusted: Bool, probe: Probe) -> Self {
        if trusted { return .granted }
        switch probe {
        case .accessible: return .granted
        case .accessDenied: return .denied
        case .inconclusive: return .unavailable
        }
    }
}
