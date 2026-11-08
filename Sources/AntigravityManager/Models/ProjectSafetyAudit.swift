import Foundation

public struct ProjectSafetyAudit: Sendable, Equatable {
    public enum AuditStatus: Sendable, Equatable {
        case passed
        case warning
        case failed
        case checking

        public var title: String {
            switch self {
            case .passed: return "PASSED"
            case .warning: return "WARNING"
            case .failed: return "FAILED"
            case .checking: return "CHECKING"
            }
        }
    }

    public struct AuditItem: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String
        public let status: AuditStatus

        public init(id: String, title: String, detail: String, status: AuditStatus) {
            self.id = id
            self.title = title
            self.detail = detail
            self.status = status
        }
    }

    public var pathCheck: AuditItem
    public var gitignoreCheck: AuditItem
    public var manifestCheck: AuditItem
    public var symlinkCheck: AuditItem

    public init(
        pathCheck: AuditItem,
        gitignoreCheck: AuditItem,
        manifestCheck: AuditItem,
        symlinkCheck: AuditItem
    ) {
        self.pathCheck = pathCheck
        self.gitignoreCheck = gitignoreCheck
        self.manifestCheck = manifestCheck
        self.symlinkCheck = symlinkCheck
    }

    public var items: [AuditItem] {
        [pathCheck, gitignoreCheck, manifestCheck, symlinkCheck]
    }

    public var overallStatus: AuditStatus {
        if items.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if items.contains(where: { $0.status == .warning }) {
            return .warning
        }
        if items.contains(where: { $0.status == .checking }) {
            return .checking
        }
        return .passed
    }

    public static func checking(for project: ProjectProfile) -> ProjectSafetyAudit {
        ProjectSafetyAudit(
            pathCheck: AuditItem(
                id: "path",
                title: "Project Directory",
                detail: "Verifying path on disk...",
                status: .checking
            ),
            gitignoreCheck: AuditItem(
                id: "gitignore",
                title: ".gitignore Protection",
                detail: "Checking Git secret protection...",
                status: .checking
            ),
            manifestCheck: AuditItem(
                id: "manifest",
                title: "Runtime Manifest",
                detail: "Inspecting mcp_config.json...",
                status: .checking
            ),
            symlinkCheck: AuditItem(
                id: "symlinks",
                title: "Asset Symlinks",
                detail: "Verifying skill isolation...",
                status: .checking
            )
        )
    }
}
