import Foundation
import Observation

@MainActor
@Observable
public final class SkillEditorState {
    public let skill: SkillDefinition

    public var content: String = ""
    public var originalContent: String = ""
    public var isLoading: Bool = true
    public var errorMessage: String? = nil
    public var statusFeedback: String? = nil
    public var targetFileURL: URL? = nil
    public var availableFiles: [URL] = []

    public init(skill: SkillDefinition) {
        self.skill = skill
    }

    public var isReadOnly: Bool {
        false
    }

    public var isModified: Bool {
        content != originalContent
    }

    public var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }

    public var characterCount: Int {
        content.count
    }

    public func discoverAndLoadFiles() {
        let baseDir = URL(fileURLWithPath: skill.path)
        var files: [URL] = []
        let fm = FileManager.default

        if baseDir.pathExtension.lowercased() == "md" {
            files.append(baseDir)
        } else {
            let mainMd = baseDir.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: mainMd.path) {
                files.append(mainMd)
            }
            files.append(contentsOf: listDirectoryFiles(at: baseDir.appendingPathComponent("references")))
            files.append(contentsOf: listDirectoryFiles(at: baseDir.appendingPathComponent("scripts")))
        }

        self.availableFiles = files

        if let first = files.first {
            loadFile(url: first)
        } else {
            let fallbackURL = baseDir.appendingPathComponent("SKILL.md")
            self.targetFileURL = fallbackURL
            self.content = """
            ---
            name: \(skill.id)
            description: \(skill.description.isEmpty ? "Skill description here" : skill.description)
            ---

            # \(skill.name)

            Write skill instructions and rules here.
            """
            self.originalContent = self.content
            self.isLoading = false
        }
    }

    private func listDirectoryFiles(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []))?
            .filter { fileURL in
                guard !fileURL.lastPathComponent.hasPrefix(".") else { return false }
                let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return !isDirectory
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    public func switchToFile(_ url: URL, onSave: ((String) -> Void)? = nil) {
        if isModified && !isReadOnly {
            saveChanges(onSave: onSave)
        }
        loadFile(url: url)
    }

    public func loadFile(url: URL) {
        self.targetFileURL = url
        self.isLoading = true
        self.errorMessage = nil

        do {
            let readText = try String(contentsOf: url, encoding: .utf8)
            self.content = readText
            self.originalContent = readText
            self.isLoading = false
        } catch {
            self.errorMessage = "Could not read file (\(url.lastPathComponent)): \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    public func discardChanges() {
        self.content = self.originalContent
        self.statusFeedback = "Changes discarded"
    }

    public func saveChanges(onSave: ((String) -> Void)? = nil) {
        guard let url = targetFileURL else { return }
        do {
            let parentDir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            originalContent = content
            statusFeedback = "✓ Saved: \(url.lastPathComponent)"
            onSave?(content)

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                if self.statusFeedback == "✓ Saved: \(url.lastPathComponent)" {
                    self.statusFeedback = nil
                }
            }
        } catch {
            statusFeedback = "Error: \(error.localizedDescription)"
        }
    }

    @discardableResult
    public func forkToVault() -> SkillDefinition? {
        let sourceURL = URL(fileURLWithPath: skill.path)
        let targetURL = PathConstants.vaultSkillsDirectory.appendingPathComponent(skill.id)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: PathConstants.vaultSkillsDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: targetURL.path) {
                try fm.removeItem(at: targetURL)
            }
            try fm.copyItem(at: sourceURL, to: targetURL)

            var newSkill = skill
            newSkill.origin = .vault
            newSkill.path = targetURL.path
            statusFeedback = "✓ Forked to Master Vault (\(skill.id))"
            return newSkill
        } catch {
            statusFeedback = "Error forking to Vault: \(error.localizedDescription)"
            return nil
        }
    }
}
