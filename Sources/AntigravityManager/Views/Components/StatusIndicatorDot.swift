import SwiftUI

public enum SemanticStatus: Sendable, Hashable {
    case active
    case projectLinked
    case inactive
    case syncing
    case error

    public var color: Color {
        switch self {
        case .active: return DesignTokens.Colors.statusActive
        case .projectLinked: return DesignTokens.Colors.statusProject
        case .inactive: return DesignTokens.Colors.statusInactive
        case .syncing: return DesignTokens.Colors.statusSyncing
        case .error: return DesignTokens.Colors.statusError
        }
    }

    public var label: String {
        switch self {
        case .active: return "Active"
        case .projectLinked: return "Project Scoped"
        case .inactive: return "Inactive"
        case .syncing: return "Synchronizing..."
        case .error: return "Error"
        }
    }
}

public struct StatusIndicatorDot: View {
    public let status: SemanticStatus
    public let size: CGFloat

    public init(status: SemanticStatus, size: CGFloat = DesignTokens.Dimensions.statusDotSize) {
        self.status = status
        self.size = size
    }

    public init(
        isActive: Bool,
        isProjectEnabled: Bool = false,
        isSyncing: Bool = false,
        size: CGFloat = DesignTokens.Dimensions.statusDotSize
    ) {
        if isSyncing {
            self.status = .syncing
        } else if isProjectEnabled {
            self.status = .projectLinked
        } else if isActive {
            self.status = .active
        } else {
            self.status = .inactive
        }
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .help(status.label)
            .accessibilityLabel(status.label)
    }
}

public typealias StatusDotView = StatusIndicatorDot
