import Foundation
import SwiftUI

public enum SyncLogStatus: String, Sendable, Codable, CaseIterable {
    case success = "SUCCESS"
    case warning = "WARNING"
    case failure = "FAILURE"
    case info = "INFO"

    public var title: String {
        switch self {
        case .success: return "Success"
        case .warning: return "Warning"
        case .failure: return "Failure"
        case .info: return "Info"
        }
    }

    public var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .success: return DesignTokens.secondary
        case .warning: return DesignTokens.tierOrange
        case .failure: return DesignTokens.Colors.statusError
        case .info: return DesignTokens.inkSecondary
        }
    }

    public var backgroundColor: Color {
        switch self {
        case .success: return DesignTokens.storeBlueTint
        case .warning: return DesignTokens.tierOrange.opacity(0.12)
        case .failure: return DesignTokens.Colors.statusError.opacity(0.12)
        case .info: return DesignTokens.surfaceContainerHigh
        }
    }
}

public enum SyncLogCategory: String, Sendable, Codable, CaseIterable {
    case all = "ALL"
    case global = "GLOBAL"
    case project = "PROJECT"
    case vault = "VAULT"
    case system = "SYSTEM"

    public var title: String {
        switch self {
        case .all: return "All Workspaces"
        case .global: return "Global Core"
        case .project: return "Project"
        case .vault: return "Master Vault"
        case .system: return "System"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "arrow.triangle.2.circlepath"
        case .global: return "globe"
        case .project: return "folder"
        case .vault: return "shield.lefthalf.filled"
        case .system: return "gearshape"
        }
    }
}

public struct SyncLogEntry: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let status: SyncLogStatus
    public let category: SyncLogCategory
    public let targetName: String
    public let message: String
    public let details: String?
    public let duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        status: SyncLogStatus,
        category: SyncLogCategory = .system,
        targetName: String,
        message: String,
        details: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.category = category
        self.targetName = targetName
        self.message = message
        self.details = details
        self.duration = duration
    }

    public var formattedDuration: String? {
        guard let duration else { return nil }
        if duration < 0.001 {
            return String(format: "%.1f µs", duration * 1_000_000)
        } else if duration < 1.0 {
            return String(format: "%.1f ms", duration * 1000)
        } else {
            return String(format: "%.2f s", duration)
        }
    }

    public var formattedTimestamp: String {
        timestamp.formatted(date: .omitted, time: .standard)
    }

    public var fullTimestamp: String {
        timestamp.formatted(date: .abbreviated, time: .complete)
    }
}
