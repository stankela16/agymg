import Foundation

public struct SkillScannerService: Sendable {
    public init() {}

    public func scanVaultSkills(readOnly: Bool = false) -> [SkillDefinition] {
        let vaultDir = PathConstants.vaultSkillsDirectory
        let fm = FileManager.default

        if !readOnly && !fm.fileExists(atPath: vaultDir.path) {
            try? fm.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        }

        return scanDirectory(vaultDir, defaultOrigin: .vault)
    }

    public func scanBuiltinSkills() -> [SkillDefinition] {
        let builtinDir = PathConstants.builtinSkillsDirectory
        return scanDirectory(builtinDir, defaultOrigin: .builtin)
    }

    public func scanProjectLocalSkills(projectPath: String) -> [SkillDefinition] {
        let skillsDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".agents/skills", isDirectory: true)
        return scanDirectory(skillsDir, defaultOrigin: .projectLocal, excludeSymlinksAndVault: true)
    }

    public func scanAllProjectLocalSkills(projects: [ProjectProfile]) -> [String: [SkillDefinition]] {
        var results: [String: [SkillDefinition]] = [:]
        for project in projects {
            results[project.id] = scanProjectLocalSkills(projectPath: project.path)
        }
        return results
    }

    private func scanDirectory(
        _ dir: URL,
        defaultOrigin: ResourceOrigin,
        excludeSymlinksAndVault: Bool = false
    ) -> [SkillDefinition] {
        let fm = FileManager.default
        guard let enumerator = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        var results: [SkillDefinition] = []
        let vaultResolved = PathConstants.vaultSkillsDirectory.resolvingSymlinksInPath().path
        let globalResolved = PathConstants.globalSkillsDirectory.resolvingSymlinksInPath().path

        for folderURL in enumerator where !folderURL.lastPathComponent.hasPrefix(".") {
            if excludeSymlinksAndVault {
                let isSymlink: Bool
                if (try? fm.destinationOfSymbolicLink(atPath: folderURL.path)) != nil {
                    isSymlink = true
                } else if let values = try? folderURL.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                    isSymlink = true
                } else {
                    isSymlink = false
                }

                if isSymlink {
                    continue
                }

                let resolved = folderURL.resolvingSymlinksInPath().path
                if resolved.hasPrefix(vaultResolved) || resolved.hasPrefix(globalResolved) {
                    continue
                }
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue {
                let skillId = folderURL.lastPathComponent
                let skillMdURL = folderURL.appendingPathComponent("SKILL.md")
                var description = ""

                if fm.fileExists(atPath: skillMdURL.path),
                   let content = try? String(contentsOf: skillMdURL, encoding: .utf8) {
                    description = extractDescription(from: content)
                }

                results.append(SkillDefinition(
                    id: skillId,
                    name: formatSkillName(skillId),
                    description: description,
                    category: SkillDefinition.guessCategory(for: skillId),
                    path: folderURL.path,
                    origin: defaultOrigin
                ))
            }
        }

        return results.sorted { $0.id < $1.id }
    }

    private func extractDescription(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var readingMultiLine = false
        var multiLineCollected: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if readingMultiLine {
                if trimmed.hasPrefix("---") || (!line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && trimmed.contains(":")) {
                    break
                }
                if !trimmed.isEmpty {
                    multiLineCollected.append(trimmed)
                }
                continue
            }

            if trimmed.lowercased().hasPrefix("description:") {
                let desc = trimmed.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                let clean = desc.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if clean == ">-" || clean == ">" || clean == "|" || clean == "|-" || clean.isEmpty {
                    readingMultiLine = true
                    continue
                } else {
                    return clean
                }
            }
        }

        if !multiLineCollected.isEmpty {
            return multiLineCollected.joined(separator: " ")
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") {
                return trimmed
            }
        }
        return ""
    }

    private func formatSkillName(_ id: String) -> String {
        id.split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
