import Foundation

public enum SkillImportError: LocalizedError, Sendable {
    case sourceNotFound(String)
    case invalidSourceURL(String)
    case missingSkillMarkdown(String)
    case invalidSkillId(String)
    case skillAlreadyExists(String)
    case gitCloneFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let msg): return msg
        case .invalidSourceURL(let msg): return msg
        case .missingSkillMarkdown(let msg): return msg
        case .invalidSkillId(let msg): return msg
        case .skillAlreadyExists(let id): return "Skill '\(id)' already exists in Master Vault (enable overwrite to replace it)."
        case .gitCloneFailed(let msg): return msg
        }
    }
}

public struct ParsedGitHubSkillURL: Sendable, Equatable {
    public let repoCloneURL: String
    public let branch: String?
    public let subpath: String?
    public let suggestedSkillId: String

    public init(repoCloneURL: String, branch: String?, subpath: String?, suggestedSkillId: String) {
        self.repoCloneURL = repoCloneURL
        self.branch = branch
        self.subpath = subpath
        self.suggestedSkillId = suggestedSkillId
    }
}

public struct SkillImportService: Sendable {
    public init() {}

    public func importFromLocalFolder(
        sourceURL: URL,
        customId: String? = nil,
        overwrite: Bool = false
    ) throws -> SkillDefinition {
        let fm = FileManager.default
        let resolvedRoot = sourceURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolvedRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillImportError.sourceNotFound("Folder does not exist: \(sourceURL.path)")
        }

        let resolvedSkillDir = try locateSkillDirectory(in: resolvedRoot, preferredId: customId)
        let rawId = (customId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customId!.trimmingCharacters(in: .whitespacesAndNewlines)
            : resolvedSkillDir.lastPathComponent

        let cleanId = Self.normalizeSkillId(rawId)
        guard !cleanId.isEmpty, PathConstants.isSafeResourceId(cleanId), !cleanId.hasPrefix(".") else {
            throw SkillImportError.invalidSkillId("Invalid skill ID derived from '\(rawId)'.")
        }

        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        try fm.createDirectory(at: vaultSkillsDir, withIntermediateDirectories: true)
        let destinationDir = vaultSkillsDir.appendingPathComponent(cleanId, isDirectory: true)

        // Prevent copying Vault folder onto itself
        if resolvedSkillDir.resolvingSymlinksInPath().path == destinationDir.resolvingSymlinksInPath().path {
            return buildSkillDefinition(id: cleanId, folderURL: destinationDir)
        }

        if fm.fileExists(atPath: destinationDir.path) {
            if overwrite {
                try fm.removeItem(at: destinationDir)
            } else {
                throw SkillImportError.skillAlreadyExists(cleanId)
            }
        }

        try fm.copyItem(at: resolvedSkillDir, to: destinationDir)

        // Strip cloned VCS metadata if importing from repository root
        let gitSubdir = destinationDir.appendingPathComponent(".git")
        if fm.fileExists(atPath: gitSubdir.path) {
            try? fm.removeItem(at: gitSubdir)
        }

        return buildSkillDefinition(id: cleanId, folderURL: destinationDir)
    }

    public func importFromGitHubURL(
        _ rawURL: String,
        customId: String? = nil,
        overwrite: Bool = false
    ) async throws -> SkillDefinition {
        let parsed = try Self.parseGitHubURL(rawURL)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agymg_skill_import_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cloneDir = tempDir.appendingPathComponent("repo", isDirectory: true)
        var gitArgs = ["clone", "--depth", "1"]
        if let branch = parsed.branch, !branch.isEmpty {
            gitArgs.append(contentsOf: ["--branch", branch])
        }
        gitArgs.append(contentsOf: [parsed.repoCloneURL, cloneDir.path])

        let cloneStatus: (code: Int32, stderr: String) = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = gitArgs
            let stderrPipe = Pipe()
            process.standardOutput = Pipe()
            process.standardError = stderrPipe
            try process.run()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, errText)
        }.value

        guard cloneStatus.code == 0 else {
            let reason = cloneStatus.stderr.isEmpty ? "git clone exited with code \(cloneStatus.code)" : cloneStatus.stderr
            throw SkillImportError.gitCloneFailed("Failed to clone GitHub repository: \(reason)")
        }

        let targetRoot: URL
        if let subpath = parsed.subpath, !subpath.isEmpty {
            targetRoot = cloneDir.appendingPathComponent(subpath, isDirectory: true)
        } else {
            targetRoot = cloneDir
        }

        let hasDirectSkillMd = FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("SKILL.md").path)
        let effectiveCustomId: String?
        if let explicit = customId?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            effectiveCustomId = explicit
        } else if hasDirectSkillMd || parsed.subpath != nil {
            effectiveCustomId = parsed.suggestedSkillId
        } else {
            effectiveCustomId = nil
        }
        return try importFromLocalFolder(sourceURL: targetRoot, customId: effectiveCustomId, overwrite: overwrite)
    }

    public static func parseGitHubURL(_ rawURL: String) throws -> ParsedGitHubSkillURL {
        var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host?.lowercased(),
              host == "github.com" else {
            throw SkillImportError.invalidSourceURL("Expected an HTTPS GitHub URL (e.g. https://github.com/owner/repo or https://github.com/owner/repo/tree/main/skills/my-skill).")
        }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count >= 2 else {
            throw SkillImportError.invalidSourceURL("GitHub URL must include owner and repository name.")
        }

        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") {
            repo = String(repo.dropLast(4))
        }
        guard isSafeURLSegment(owner), isSafeURLSegment(repo) else {
            throw SkillImportError.invalidSourceURL("GitHub owner or repository name contains invalid characters.")
        }

        var branch: String? = nil
        var subpath: String? = nil
        if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
            let rawBranch = parts[3]
            guard isSafeURLSegment(rawBranch) else {
                throw SkillImportError.invalidSourceURL("GitHub branch name contains invalid characters.")
            }
            branch = rawBranch
            if parts.count > 4 {
                let tail = Array(parts[4...])
                guard tail.allSatisfy({ isSafeURLSegment($0) }) else {
                    throw SkillImportError.invalidSourceURL("GitHub URL subpath contains unsafe segments.")
                }
                subpath = tail.joined(separator: "/")
            }
        }

        let suggestedRaw = subpath?.split(separator: "/").last.map(String.init) ?? repo
        let suggestedId = normalizeSkillId(suggestedRaw)
        guard !suggestedId.isEmpty else {
            throw SkillImportError.invalidSourceURL("Could not derive skill ID from GitHub URL.")
        }

        return ParsedGitHubSkillURL(
            repoCloneURL: "https://github.com/\(owner)/\(repo).git",
            branch: branch,
            subpath: subpath,
            suggestedSkillId: suggestedId
        )
    }

    // MARK: - Helpers
    private func locateSkillDirectory(in rootURL: URL, preferredId: String?) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: rootURL.appendingPathComponent("SKILL.md").path) {
            return rootURL
        }

        // Support repo structure containing skills/<skill-id>/SKILL.md
        let skillsContainer = rootURL.appendingPathComponent("skills", isDirectory: true)
        if let subdirs = try? fm.contentsOfDirectory(
            at: skillsContainer,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let skillDirs = subdirs.filter { dir in
                fm.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path)
            }
            if let preferred = preferredId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !preferred.isEmpty,
               let match = skillDirs.first(where: { $0.lastPathComponent.lowercased() == preferred }) {
                return match
            }
            if skillDirs.count == 1, let only = skillDirs.first {
                return only
            }
            if skillDirs.count > 1 {
                let names = skillDirs.map(\.lastPathComponent).sorted().joined(separator: ", ")
                throw SkillImportError.missingSkillMarkdown("Multiple skills found under skills/ (\(names)). Specify a subpath or matching Skill ID.")
            }
        }

        throw SkillImportError.missingSkillMarkdown("No SKILL.md found in '\(rootURL.lastPathComponent)'.")
    }

    private func buildSkillDefinition(id: String, folderURL: URL) -> SkillDefinition {
        let scanner = SkillScannerService()
        let skillMd = folderURL.appendingPathComponent("SKILL.md")
        var description = ""
        var customName: String? = nil
        if let content = try? String(contentsOf: skillMd, encoding: .utf8) {
            description = scanner.extractDescription(from: content)
            customName = Self.extractName(from: content)
        }
        let displayName = (customName?.isEmpty == false) ? customName! : scanner.formatSkillName(id)
        return SkillDefinition(
            id: id,
            name: displayName,
            description: description,
            category: SkillDefinition.guessCategory(for: id),
            path: folderURL.path,
            origin: .vault
        )
    }

    private static func extractName(from content: String) -> String? {
        for rawLine in content.components(separatedBy: .newlines).prefix(20) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("name:") {
                let val = trimmed.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
                let clean = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return clean.isEmpty ? nil : clean
            }
        }
        return nil
    }

    public static func normalizeSkillId(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = lower.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func isSafeURLSegment(_ seg: String) -> Bool {
        guard !seg.isEmpty, seg != ".", seg != "..",
              !seg.contains("/"), !seg.contains("\\"), !seg.contains("\0"),
              !seg.contains("..") else {
            return false
        }
        return seg.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}
