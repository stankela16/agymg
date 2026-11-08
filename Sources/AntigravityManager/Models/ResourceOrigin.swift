import Foundation

public enum ResourceOrigin: String, Codable, Sendable, CaseIterable {
    case builtin = "Built-in System"
    case global = "Global Profile"
    case projectLocal = "Project Local"
    case vault = "Master Vault"

    public var badgeIcon: String {
        switch self {
        case .builtin: return "shield.fill"
        case .global: return "globe"
        case .projectLocal: return "folder.fill"
        case .vault: return "archivebox.fill"
        }
    }
}
