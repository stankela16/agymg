import Foundation
import AppKit
import Darwin

public struct CLIExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct CLISafeResourceItem: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let category: String?
    public let description: String?

    public init(id: String, name: String, category: String? = nil, description: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
    }
}

public struct CLIBriefProjectSection: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let isRegistered: Bool
    public let stackLabels: [String]
    public let isEmptyProjectSetup: Bool
}

public struct CLIBriefActiveSection: Codable, Sendable, Equatable {
    public let projectMCPs: [CLISafeResourceItem]
    public let globalMCPs: [CLISafeResourceItem]
    public let projectSkills: [CLISafeResourceItem]
    public let localSkills: [CLISafeResourceItem]
    public let globalSkills: [CLISafeResourceItem]
    public let projectPlugins: [CLISafeResourceItem]
    public let globalPlugins: [CLISafeResourceItem]
}

public struct CLIBriefCatalogSection: Codable, Sendable, Equatable {
    public let inactiveMCPs: [CLISafeResourceItem]
    public let inactiveSkills: [CLISafeResourceItem]
    public let inactivePlugins: [CLISafeResourceItem]
}

public struct CLIBriefResponse: Codable, Sendable, Equatable {
    public let project: CLIBriefProjectSection
    public let active: CLIBriefActiveSection
    public let recommendations: [ResourceRecommendation]
    public let vaultCatalog: CLIBriefCatalogSection
}

public struct CLISetResponse: Codable, Sendable, Equatable {
    public let scope: String
    public let targetId: String
    public let targetPath: String?
    public let enabledMCPs: [String]
    public let disabledMCPs: [String]
    public let enabledSkills: [String]
    public let disabledSkills: [String]
    public let enabledPlugins: [String]
    public let disabledPlugins: [String]
    public let unknownIds: [String]
    public let requiresSessionReloadForMCP: Bool
    public let message: String
}

public enum CLIRunner {
    public static var currentVersion: String {
        if Bundle.main.bundleURL.pathExtension == "app",
           let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundled.isEmpty {
            return bundled
        }
        return PathConstants.appVersion
    }

    public static let supportedSubcommands: Set<String> = [
        "brief",
        "set",
        "hook-session-start",
        "install-app",
        "uninstall",
        "help",
        "--help",
        "-h",
        "--version",
        "-v"
    ]

    public static func shouldHandle(arguments: [String]) -> Bool {
        guard arguments.count > 1 else { return false }
        let firstArg = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return supportedSubcommands.contains(firstArg)
    }

    public static func runFromCommandLine(arguments: [String]) -> Int32 {
        let subcommand = arguments.count > 1 ? arguments[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let stdinData: Data? = (subcommand == "hook-session-start") ? readNonBlockingStdinIfPiped() : nil
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            let res = await execute(arguments: arguments, stdinData: stdinData)
            box.set(res)
            semaphore.signal()
        }
        semaphore.wait()

        let result = box.get()
        if !result.stdout.isEmpty {
            FileHandle.standardOutput.write(Data(result.stdout.utf8))
            if !result.stdout.hasSuffix("\n") {
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
            if !result.stderr.hasSuffix("\n") {
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }
        return result.exitCode
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = CLIExecutionResult(exitCode: 0)
        func set(_ newValue: CLIExecutionResult) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
        func get() -> CLIExecutionResult {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    public static func readNonBlockingStdinIfPiped(from fd: Int32 = STDIN_FILENO, initialTimeoutMs: Int32 = 80) -> Data? {
        guard isatty(fd) == 0 else { return nil }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var isFirstChunk = true

        while true {
            var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let timeout: Int32 = isFirstChunk ? initialTimeoutMs : 10
            let ready = poll(&pollFd, 1, timeout)
            guard ready > 0 && (pollFd.revents & Int16(POLLIN | POLLHUP)) != 0 else {
                break
            }
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            isFirstChunk = false
            if bytesRead > 0 {
                collected.append(contentsOf: buffer[0..<bytesRead])
                if collected.count > 262_144 { break }
            } else {
                break
            }
        }
        return collected.isEmpty ? nil : collected
    }

    public static func execute(
        arguments: [String],
        stdinData: Data? = nil,
        currentDirectoryPath: String? = nil
    ) async -> CLIExecutionResult {
        let args = Array(arguments.dropFirst())
        guard let subcommand = args.first else {
            return CLIExecutionResult(exitCode: 1, stderr: helpText)
        }

        switch subcommand {
        case "help", "--help", "-h":
            return CLIExecutionResult(exitCode: 0, stdout: helpText)
        case "--version", "-v":
            return CLIExecutionResult(exitCode: 0, stdout: "agymg \(currentVersion)")
        case "brief":
            return await handleBrief(
                args: Array(args.dropFirst()),
                currentDirectoryPath: currentDirectoryPath ?? FileManager.default.currentDirectoryPath
            )
        case "set":
            return await handleSet(
                args: Array(args.dropFirst()),
                currentDirectoryPath: currentDirectoryPath ?? FileManager.default.currentDirectoryPath
            )
        case "hook-session-start":
            return await handleHookSessionStart(
                args: Array(args.dropFirst()),
                stdinData: stdinData,
                currentDirectoryPath: currentDirectoryPath ?? FileManager.default.currentDirectoryPath
            )
        case "install-app":
            return handleInstallApp(
                args: Array(args.dropFirst()),
                currentDirectoryPath: currentDirectoryPath ?? FileManager.default.currentDirectoryPath
            )
        case "uninstall":
            return await handleUninstall(args: Array(args.dropFirst()))
        default:
            return CLIExecutionResult(exitCode: 1, stderr: "Unknown subcommand '\(subcommand)'.\n\n\(helpText)")
        }
    }

    // MARK: - Subcommand: brief
    private static func handleBrief(args: [String], currentDirectoryPath: String) async -> CLIExecutionResult {
        var requestedPath: String? = nil
        var outputJSON = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--json" {
                outputJSON = true
            } else if arg == "--project", i + 1 < args.count {
                requestedPath = args[i + 1]
                i += 1
            } else if arg.hasPrefix("--project=") {
                requestedPath = String(arg.dropFirst("--project=".count))
            }
            i += 1
        }

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()

        let rawPath = resolveCLIPath(requestedPath, relativeTo: currentDirectoryPath)
        let snapshot = await buildSnapshot(for: rawPath, vault: vault, source: "cli-brief", readOnly: false)

        if outputJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(snapshot),
               let jsonString = String(data: data, encoding: .utf8) {
                return CLIExecutionResult(exitCode: 0, stdout: jsonString)
            }
            return CLIExecutionResult(exitCode: 1, stderr: "Failed to encode brief JSON")
        }

        return CLIExecutionResult(exitCode: 0, stdout: formatBriefMarkdown(snapshot))
    }

    // MARK: - Subcommand: set
    private static func handleSet(args: [String], currentDirectoryPath: String) async -> CLIExecutionResult {
        var requestedPath: String? = nil
        var isGlobal = false
        var outputJSON = false

        var enableMCP: [String] = []
        var disableMCP: [String] = []
        var enableSkill: [String] = []
        var disableSkill: [String] = []
        var enablePlugin: [String] = []
        var disablePlugin: [String] = []

        func parseList(_ raw: String) -> [String] {
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--global":
                isGlobal = true
            case "--json":
                outputJSON = true
            case "--project":
                if i + 1 < args.count {
                    requestedPath = args[i + 1]
                    i += 1
                }
            case "--enable-mcp":
                if i + 1 < args.count {
                    enableMCP.append(contentsOf: parseList(args[i + 1]))
                    i += 1
                }
            case "--disable-mcp":
                if i + 1 < args.count {
                    disableMCP.append(contentsOf: parseList(args[i + 1]))
                    i += 1
                }
            case "--enable-skill":
                if i + 1 < args.count {
                    enableSkill.append(contentsOf: parseList(args[i + 1]))
                    i += 1
                }
            case "--disable-skill":
                if i + 1 < args.count {
                    disableSkill.append(contentsOf: parseList(args[i + 1]))
                    i += 1
                }
            case "--enable-plugin":
                if i + 1 < args.count {
                    enablePlugin.append(contentsOf: parseList(args[i + 1]))
                    i += 1
                }
            case "--disable-plugin":
                if i + 1 < args.count {
                    disablePlugin.append(contentsOf: parseList(args[i + 1]))
                    i += 1
                }
            default:
                if arg.hasPrefix("--project=") {
                    requestedPath = String(arg.dropFirst("--project=".count))
                } else if arg.hasPrefix("--enable-mcp=") {
                    enableMCP.append(contentsOf: parseList(String(arg.dropFirst("--enable-mcp=".count))))
                } else if arg.hasPrefix("--disable-mcp=") {
                    disableMCP.append(contentsOf: parseList(String(arg.dropFirst("--disable-mcp=".count))))
                } else if arg.hasPrefix("--enable-skill=") {
                    enableSkill.append(contentsOf: parseList(String(arg.dropFirst("--enable-skill=".count))))
                } else if arg.hasPrefix("--disable-skill=") {
                    disableSkill.append(contentsOf: parseList(String(arg.dropFirst("--disable-skill=".count))))
                } else if arg.hasPrefix("--enable-plugin=") {
                    enablePlugin.append(contentsOf: parseList(String(arg.dropFirst("--enable-plugin=".count))))
                } else if arg.hasPrefix("--disable-plugin=") {
                    disablePlugin.append(contentsOf: parseList(String(arg.dropFirst("--disable-plugin=".count))))
                }
            }
            i += 1
        }

        let hasAnyMutation = !enableMCP.isEmpty || !disableMCP.isEmpty
            || !enableSkill.isEmpty || !disableSkill.isEmpty
            || !enablePlugin.isEmpty || !disablePlugin.isEmpty

        guard hasAnyMutation else {
            return CLIExecutionResult(
                exitCode: 1,
                stderr: "No resource changes specified. Use --enable-mcp, --disable-mcp, --enable-skill, --disable-skill, --enable-plugin, or --disable-plugin."
            )
        }

        let vault = VaultService()
        await vault.initializeVaultIfNeeded()
        let syncEngine = SyncEngine()
        let skillScanner = SkillScannerService()
        let pluginScanner = PluginScannerService()

        let targetRawPath = isGlobal ? nil : resolveCLIPath(requestedPath, relativeTo: currentDirectoryPath)
        var projects = await vault.loadSavedProjectsWithoutTCC(allowingCWD: targetRawPath)
        let safeProjects = projects.filter { canSafelyScanProject($0.path, allowingCWD: targetRawPath) }
        let (allServers, _) = await vault.scanAndIngestServers(projects: safeProjects)
        let allSkills = skillScanner.scanVaultSkills()
        let allPlugins = pluginScanner.scanAllPlugins(projects: safeProjects)

        let validServerIds = Set(allServers.map(\.id))
        let validSkillIds = Set(allSkills.map(\.id))
        let validPluginIds = Set(allPlugins.map(\.id))

        var unknownIds: [String] = []
        let validEnableMCP = enableMCP.filter { id in
            if validServerIds.contains(id) { return true }
            unknownIds.append("mcp:\(id)")
            return false
        }
        let validDisableMCP = disableMCP.filter { id in
            if validServerIds.contains(id) { return true }
            unknownIds.append("mcp:\(id)")
            return false
        }
        let validEnableSkill = enableSkill.filter { id in
            if validSkillIds.contains(id) { return true }
            unknownIds.append("skill:\(id)")
            return false
        }
        let validDisableSkill = disableSkill.filter { id in
            if validSkillIds.contains(id) { return true }
            unknownIds.append("skill:\(id)")
            return false
        }
        let validEnablePlugin = enablePlugin.filter { id in
            if validPluginIds.contains(id) { return true }
            unknownIds.append("plugin:\(id)")
            return false
        }
        let validDisablePlugin = disablePlugin.filter { id in
            if validPluginIds.contains(id) { return true }
            unknownIds.append("plugin:\(id)")
            return false
        }

        let pluginHasMCP = Set(allPlugins.filter(\.hasMCP).map(\.id))
        let touchedMCPViaPlugin = !(Set(validEnablePlugin + validDisablePlugin).intersection(pluginHasMCP).isEmpty)
        let requiresReload = !validEnableMCP.isEmpty || !validDisableMCP.isEmpty || touchedMCPViaPlugin

        if isGlobal {
            var selection = await vault.loadGlobalSelection()
            selection.enabledMCPServerIds.formUnion(validEnableMCP)
            selection.enabledMCPServerIds.subtract(validDisableMCP)
            selection.enabledSkillIds.formUnion(validEnableSkill)
            selection.enabledSkillIds.subtract(validDisableSkill)
            selection.enabledPluginIds.formUnion(validEnablePlugin)
            selection.enabledPluginIds.subtract(validDisablePlugin)

            await vault.saveGlobalSelection(selection)
            do {
                try await syncEngine.syncGlobalConfig(servers: allServers, enabledIds: selection.enabledMCPServerIds)
                try await syncEngine.syncGlobalSkills(allSkills: allSkills, enabledSkillIds: selection.enabledSkillIds)
                try await syncEngine.syncGlobalPlugins(allPlugins: allPlugins, enabledPluginIds: selection.enabledPluginIds)
            } catch {
                return CLIExecutionResult(exitCode: 1, stderr: "Global sync error: \(error.localizedDescription)")
            }

            notifyMenuBarApp(projectPath: currentDirectoryPath, projectId: nil, projectName: nil, source: "cli-set", didMutateVault: true)

            let response = CLISetResponse(
                scope: "global",
                targetId: "global",
                targetPath: nil,
                enabledMCPs: validEnableMCP,
                disabledMCPs: validDisableMCP,
                enabledSkills: validEnableSkill,
                disabledSkills: validDisableSkill,
                enabledPlugins: validEnablePlugin,
                disabledPlugins: validDisablePlugin,
                unknownIds: unknownIds,
                requiresSessionReloadForMCP: requiresReload,
                message: buildSetSummaryMessage(
                    targetName: "Global Core",
                    enabledMCP: validEnableMCP,
                    disabledMCP: validDisableMCP,
                    enabledSkill: validEnableSkill,
                    disabledSkill: validDisableSkill,
                    enabledPlugin: validEnablePlugin,
                    disabledPlugin: validDisablePlugin,
                    unknownIds: unknownIds,
                    requiresReload: requiresReload
                )
            )
            return formatSetOutput(response, asJSON: outputJSON)
        } else {
            let rawPath = targetRawPath ?? resolveCLIPath(nil, relativeTo: currentDirectoryPath)
            let (resolvedProject, isExistingInList) = resolveOrCreateProject(for: rawPath, in: projects)
            var targetProject = resolvedProject

            // Also respect local skills in <project>/.agents/skills when disabling/enabling
            let localSkillIds = Set(skillScanner.scanProjectLocalSkills(projectPath: targetProject.path).map(\.id))
            let filteredDisableSkill = validDisableSkill.filter { !localSkillIds.contains($0) }

            targetProject.enabledMCPServerIds.formUnion(validEnableMCP)
            targetProject.enabledMCPServerIds.subtract(validDisableMCP)
            targetProject.enabledSkillIds.formUnion(validEnableSkill)
            targetProject.enabledSkillIds.subtract(filteredDisableSkill)
            targetProject.enabledPluginIds.formUnion(validEnablePlugin)
            targetProject.enabledPluginIds.subtract(validDisablePlugin)

            if isExistingInList, let idx = projects.firstIndex(where: { $0.id == targetProject.id || $0.path == targetProject.path }) {
                projects[idx] = targetProject
            } else {
                projects.append(targetProject)
                projects.sort { $0.name.lowercased() < $1.name.lowercased() }
            }

            await vault.saveProjects(projects)
            do {
                try await syncEngine.syncProject(
                    project: targetProject,
                    allServers: allServers,
                    allSkills: allSkills,
                    allPlugins: allPlugins
                )
            } catch {
                return CLIExecutionResult(exitCode: 1, stderr: "Project sync error: \(error.localizedDescription)")
            }

            let ctx = ActiveWorkspaceContext(
                projectPath: targetProject.path,
                projectId: targetProject.id,
                projectName: targetProject.name,
                source: "cli-set",
                updatedAt: Date()
            )
            await vault.saveActiveContext(ctx)
            notifyMenuBarApp(
                projectPath: targetProject.path,
                projectId: targetProject.id,
                projectName: targetProject.name,
                source: "cli-set",
                didMutateVault: true
            )

            let response = CLISetResponse(
                scope: "project",
                targetId: targetProject.id,
                targetPath: targetProject.path,
                enabledMCPs: validEnableMCP,
                disabledMCPs: validDisableMCP,
                enabledSkills: validEnableSkill,
                disabledSkills: filteredDisableSkill,
                enabledPlugins: validEnablePlugin,
                disabledPlugins: validDisablePlugin,
                unknownIds: unknownIds,
                requiresSessionReloadForMCP: requiresReload,
                message: buildSetSummaryMessage(
                    targetName: targetProject.name,
                    enabledMCP: validEnableMCP,
                    disabledMCP: validDisableMCP,
                    enabledSkill: validEnableSkill,
                    disabledSkill: filteredDisableSkill,
                    enabledPlugin: validEnablePlugin,
                    disabledPlugin: validDisablePlugin,
                    unknownIds: unknownIds,
                    requiresReload: requiresReload
                )
            )
            return formatSetOutput(response, asJSON: outputJSON)
        }
    }

    // MARK: - Subcommand: hook-session-start
    private static func handleHookSessionStart(
        args: [String],
        stdinData: Data?,
        currentDirectoryPath: String
    ) async -> CLIExecutionResult {
        var format = "antigravity"
        var requestedPath: String? = nil

        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--format", i + 1 < args.count {
                format = args[i + 1].lowercased()
                i += 1
            } else if arg.hasPrefix("--format=") {
                format = String(arg.dropFirst("--format=".count)).lowercased()
            } else if arg == "--project", i + 1 < args.count {
                requestedPath = args[i + 1]
                i += 1
            } else if arg.hasPrefix("--project=") {
                requestedPath = String(arg.dropFirst("--project=".count))
            }
            i += 1
        }

        // Extract workspace path from stdin JSON payload if not explicitly passed
        if requestedPath == nil, let stdinData, !stdinData.isEmpty {
            if let json = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] {
                let rawPaths = (json["workspacePaths"] as? [String]) ?? (json["workspace_paths"] as? [String])
                if let firstWS = rawPaths?.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    requestedPath = normalizeHookPath(firstWS)
                } else if let cwd = json["cwd"] as? String, !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    requestedPath = normalizeHookPath(cwd)
                }
            }
        }

        let targetRawPath = resolveCLIPath(requestedPath, relativeTo: currentDirectoryPath)
        let vault = VaultService()

        let snapshot = await buildSnapshot(for: targetRawPath, vault: vault, source: "session-start", readOnly: true)

        if format == "claude-text" {
            let text = formatClaudeSessionStartText(snapshot)
            return CLIExecutionResult(exitCode: 0, stdout: text)
        } else {
            let json = formatAntigravitySessionStartJSON(snapshot)
            return CLIExecutionResult(exitCode: 0, stdout: json)
        }
    }

    private static func normalizeHookPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url.path
        }
        return trimmed
    }

    private static func resolveCLIPath(_ requestedPath: String?, relativeTo currentDirectoryPath: String) -> String {
        let baseURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true).standardizedFileURL
        guard let raw = requestedPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return baseURL.path
        }
        let cleaned = normalizeHookPath(raw)
        let expanded = (cleaned as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        return URL(fileURLWithPath: expanded, relativeTo: baseURL).standardizedFileURL.path
    }

    private static func canSafelyScanProject(_ projectPath: String, allowingCWD cwd: String?) -> Bool {
        if !PathConstants.isTCCProtectedPath(projectPath) {
            return true
        }
        guard let cwd else { return false }
        let stdCWD = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let stdProj = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        return stdCWD == stdProj || stdCWD.hasPrefix(stdProj + "/")
    }

    // MARK: - Subcommand: install-app
    private static func handleInstallApp(args: [String], currentDirectoryPath: String) -> CLIExecutionResult {
        var customDestDir: String? = nil
        var customSourceApp: String? = nil

        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--dest", i + 1 < args.count {
                customDestDir = args[i + 1]
                i += 1
            } else if arg.hasPrefix("--dest=") {
                customDestDir = String(arg.dropFirst("--dest=".count))
            } else if arg == "--source", i + 1 < args.count {
                customSourceApp = args[i + 1]
                i += 1
            } else if arg.hasPrefix("--source=") {
                customSourceApp = String(arg.dropFirst("--source=".count))
            }
            i += 1
        }

        let fm = FileManager.default
        var candidateSources: [URL] = []
        if let customSourceApp, !customSourceApp.isEmpty {
            let explicitURL = URL(fileURLWithPath: customSourceApp)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: explicitURL.path, isDirectory: &isDir), isDir.boolValue else {
                return CLIExecutionResult(exitCode: 1, stderr: "Source app bundle does not exist at '\(explicitURL.path)'.")
            }
            candidateSources.append(explicitURL)
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            candidateSources.append(Bundle.main.bundleURL)
        }
        if let execURL = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let maybeApp = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if maybeApp.pathExtension == "app" {
                candidateSources.append(maybeApp)
            }
            let siblingLibexec = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("libexec/agymg.app")
            candidateSources.append(siblingLibexec)
        }
        candidateSources.append(URL(fileURLWithPath: "/opt/homebrew/opt/agymg/libexec/agymg.app"))
        candidateSources.append(URL(fileURLWithPath: "/usr/local/opt/agymg/libexec/agymg.app"))
        candidateSources.append(URL(fileURLWithPath: currentDirectoryPath).appendingPathComponent("agymg.app"))

        guard let sourceApp = candidateSources.first(where: { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }) else {
            return CLIExecutionResult(
                exitCode: 1,
                stderr: "Could not locate packaged agymg.app bundle. Run './Scripts/package_app.sh release' first or reinstall via Homebrew."
            )
        }

        let destDirURL: URL
        if let customDestDir, !customDestDir.isEmpty {
            destDirURL = URL(fileURLWithPath: customDestDir, isDirectory: true)
        } else if fm.isWritableFile(atPath: "/Applications") {
            destDirURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        } else {
            destDirURL = PathConstants.effectiveHomeDirectory.appendingPathComponent("Applications", isDirectory: true)
        }

        do {
            try fm.createDirectory(at: destDirURL, withIntermediateDirectories: true)
        } catch {
            return CLIExecutionResult(exitCode: 1, stderr: "Failed to prepare destination directory '\(destDirURL.path)': \(error.localizedDescription)")
        }

        let destAppURL = destDirURL.appendingPathComponent("agymg.app", isDirectory: true)
        if sourceApp.resolvingSymlinksInPath().path == destAppURL.resolvingSymlinksInPath().path {
            return CLIExecutionResult(exitCode: 0, stdout: "agymg.app is already installed at \(destAppURL.path)")
        }

        if fm.fileExists(atPath: destAppURL.path) {
            do {
                try fm.removeItem(at: destAppURL)
            } catch {
                return CLIExecutionResult(exitCode: 1, stderr: "Failed to replace existing '\(destAppURL.path)': \(error.localizedDescription)")
            }
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = [sourceApp.path, destAppURL.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
            if ditto.terminationStatus != 0 {
                return CLIExecutionResult(exitCode: ditto.terminationStatus, stderr: "ditto failed while copying agymg.app to \(destAppURL.path)")
            }
        } catch {
            return CLIExecutionResult(exitCode: 1, stderr: "Failed to copy agymg.app: \(error.localizedDescription)")
        }

        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", destAppURL.path]
        xattr.standardOutput = Pipe()
        xattr.standardError = Pipe()
        try? xattr.run()
        xattr.waitUntilExit()

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", destAppURL.path]
        verify.standardOutput = Pipe()
        verify.standardError = Pipe()
        try? verify.run()
        verify.waitUntilExit()
        if verify.terminationStatus != 0 {
            let resign = Process()
            resign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            resign.arguments = ["--force", "--deep", "--sign", "-", "--timestamp=none", destAppURL.path]
            resign.standardOutput = Pipe()
            resign.standardError = Pipe()
            try? resign.run()
            resign.waitUntilExit()
        }

        return CLIExecutionResult(
            exitCode: 0,
            stdout: "Installed agymg.app to \(destAppURL.path)"
        )
    }

    // MARK: - Subcommand: uninstall
    private static func handleUninstall(args: [String]) async -> CLIExecutionResult {
        var restore = false
        var purgeVault = false
        var outputJSON = false

        for arg in args {
            switch arg {
            case "--restore":
                restore = true
            case "--purge-vault":
                purgeVault = true
            case "--json":
                outputJSON = true
            default:
                return CLIExecutionResult(
                    exitCode: 1,
                    stderr: "Unknown flag '\(arg)' for 'uninstall'. Usage: agymg uninstall --restore [--purge-vault] [--json]"
                )
            }
        }

        guard restore else {
            return CLIExecutionResult(
                exitCode: 1,
                stderr: "Usage: agymg uninstall --restore [--purge-vault] [--json]\nPass --restore to convert symlinked skills/plugins back into standalone directories and clean agymg wrappers and hooks."
            )
        }

        if !PathConstants.isRunningUnderTests {
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.nikolastanojevic.agymg")
            for app in runningApps where app.processIdentifier != selfPID {
                _ = app.terminate()
            }
        }

        var projects: [ProjectProfile] = []
        if let data = try? Data(contentsOf: PathConstants.vaultProjectsFile),
           let saved = try? JSONDecoder().decode([ProjectProfile].self, from: data) {
            projects = saved
        } else {
            let vault = VaultService()
            projects = await vault.loadSavedProjectsWithoutTCC()
        }

        let syncEngine = SyncEngine()
        do {
            let summary = try await syncEngine.uninstallAndRestore(projects: projects, purgeVault: purgeVault)
            if outputJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let data = try encoder.encode(summary)
                let str = String(data: data, encoding: .utf8) ?? "{}"
                return CLIExecutionResult(exitCode: 0, stdout: str)
            }

            var lines: [String] = []
            lines.append("Restored standalone agent configuration successfully:")
            lines.append("- Restored global skills: \(summary.restoredGlobalSkills.count)")
            lines.append("- Restored global plugins: \(summary.restoredGlobalPlugins.count)")
            lines.append("- Removed project agy-manager wrappers: \(summary.removedProjectWrappers.count)")
            lines.append("- Removed project Vault symlinks: \(summary.removedProjectSymlinks.count)")
            lines.append("- Removed Claude OAuth helper script: \(summary.removedHelperScript ? "yes" : "no")")
            lines.append("- Cleaned Claude SessionStart hooks: \(summary.cleanedClaudeHooks ? "yes" : "no")")
            if summary.purgedVault {
                lines.append("- Purged Master Vault: \(summary.vaultPath)")
            } else {
                lines.append("- Preserved Master Vault & backups at: \(summary.vaultPath) (pass --purge-vault to delete)")
            }
            lines.append("")
            lines.append("To remove the app bundle and CLI binary:")
            lines.append("  brew uninstall agymg")
            lines.append("  rm -rf /Applications/agymg.app ~/Applications/agymg.app /opt/homebrew/bin/agymg /usr/local/bin/agymg ~/.local/bin/agymg")
            return CLIExecutionResult(exitCode: 0, stdout: lines.joined(separator: "\n"))
        } catch {
            return CLIExecutionResult(exitCode: 1, stderr: "Uninstall restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Snapshot & Resolution Helpers
    private static func buildSnapshot(
        for rawPath: String,
        vault: VaultService,
        source: String,
        readOnly: Bool
    ) async -> CLIBriefResponse {
        let projects = await vault.loadSavedProjectsWithoutTCC(allowingCWD: rawPath)
        let servers: [MCPServerDefinition]
        if readOnly {
            servers = await vault.loadServersReadOnly()
        } else {
            let safeProjects = projects.filter { canSafelyScanProject($0.path, allowingCWD: rawPath) }
            let (scanned, _) = await vault.scanAndIngestServers(projects: safeProjects)
            servers = scanned
        }
        let globalSelection = await vault.loadGlobalSelection()

        let skillScanner = SkillScannerService()
        let pluginScanner = PluginScannerService()
        let recService = ProjectRecommendationService()

        let allSkills = skillScanner.scanVaultSkills(readOnly: readOnly)
        let allPlugins: [PluginDefinition]
        if readOnly {
            allPlugins = pluginScanner.scanAllPlugins(projects: [], readOnly: true)
        } else {
            let safeProjects = projects.filter { canSafelyScanProject($0.path, allowingCWD: rawPath) }
            allPlugins = pluginScanner.scanAllPlugins(projects: safeProjects, readOnly: false)
        }

        let (project, isRegistered) = resolveOrCreateProject(for: rawPath, in: projects)
        let localSkills = skillScanner.scanProjectLocalSkills(projectPath: project.path)
        let localSkillIds = Set(localSkills.map(\.id))

        let stack = recService.inspectStack(at: project.path)
        let recommendations = recService.buildRecommendations(
            stack: stack,
            project: project,
            availableServers: servers,
            globalServerIds: globalSelection.enabledMCPServerIds,
            availableSkills: allSkills,
            globalSkillIds: globalSelection.enabledSkillIds,
            projectLocalSkillIds: localSkillIds,
            availablePlugins: allPlugins,
            globalPluginIds: globalSelection.enabledPluginIds
        )

        // Save active context only if Vault already exists (when readOnly) or unconditionally for interactive brief
        let vaultAlreadyExists = FileManager.default.fileExists(atPath: PathConstants.vaultDirectory.path)
        if !readOnly || vaultAlreadyExists {
            let context = ActiveWorkspaceContext(
                projectPath: project.path,
                projectId: project.id,
                projectName: project.name,
                source: source,
                updatedAt: Date()
            )
            await vault.saveActiveContext(context)
        }
        notifyMenuBarApp(
            projectPath: project.path,
            projectId: project.id,
            projectName: project.name,
            source: source,
            didMutateVault: false
        )

        let projectMCPs = servers
            .filter { project.enabledMCPServerIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category) }

        let globalMCPs = servers
            .filter { globalSelection.enabledMCPServerIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category) }

        let projectSkills = allSkills
            .filter { project.enabledSkillIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category, description: $0.description) }

        let projectSkillIdSet = Set(projectSkills.map(\.id))
        let localSkillItems = localSkills
            .filter { !projectSkillIdSet.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category, description: $0.description) }

        let globalSkills = allSkills
            .filter { globalSelection.enabledSkillIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category, description: $0.description) }

        let projectPlugins = allPlugins
            .filter { project.enabledPluginIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, description: $0.description) }

        let globalPlugins = allPlugins
            .filter { globalSelection.enabledPluginIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, description: $0.description) }

        let activeServerIds = globalSelection.enabledMCPServerIds.union(project.enabledMCPServerIds)
        let activeSkillIds = globalSelection.enabledSkillIds.union(project.enabledSkillIds).union(localSkillIds)
        let activePluginIds = globalSelection.enabledPluginIds.union(project.enabledPluginIds)

        let inactiveMCPs = servers
            .filter { !activeServerIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category) }

        let inactiveSkills = allSkills
            .filter { !activeSkillIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, category: $0.category, description: $0.description) }

        let inactivePlugins = allPlugins
            .filter { !activePluginIds.contains($0.id) }
            .map { CLISafeResourceItem(id: $0.id, name: $0.name, description: $0.description) }

        let isEmptySetup = projectMCPs.isEmpty
            && projectSkills.isEmpty
            && localSkillItems.isEmpty
            && projectPlugins.isEmpty

        return CLIBriefResponse(
            project: CLIBriefProjectSection(
                id: project.id,
                name: project.name,
                path: project.path,
                isRegistered: isRegistered,
                stackLabels: stack.stackLabels,
                isEmptyProjectSetup: isEmptySetup
            ),
            active: CLIBriefActiveSection(
                projectMCPs: projectMCPs,
                globalMCPs: globalMCPs,
                projectSkills: projectSkills,
                localSkills: localSkillItems,
                globalSkills: globalSkills,
                projectPlugins: projectPlugins,
                globalPlugins: globalPlugins
            ),
            recommendations: recommendations,
            vaultCatalog: CLIBriefCatalogSection(
                inactiveMCPs: inactiveMCPs,
                inactiveSkills: inactiveSkills,
                inactivePlugins: inactivePlugins
            )
        )
    }

    public static func resolveOrCreateProject(
        for rawPath: String,
        in projects: [ProjectProfile]
    ) -> (project: ProjectProfile, isRegistered: Bool) {
        let fm = FileManager.default
        let stdInput = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let canonicalInput = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().path

        func safeProjectPath(_ projPath: String) -> String {
            let stdProj = URL(fileURLWithPath: projPath).standardizedFileURL.path
            if PathConstants.isTCCProtectedPath(projPath)
                && stdInput != stdProj
                && !stdInput.hasPrefix(stdProj + "/") {
                return stdProj
            }
            return URL(fileURLWithPath: projPath).resolvingSymlinksInPath().path
        }

        // 1. Match longest registered project path prefix (handles subdirectories and nested monorepo packages)
        let annotated = projects.map { (proj: $0, canonical: safeProjectPath($0.path)) }
            .sorted { $0.canonical.count > $1.canonical.count }
        for entry in annotated {
            if canonicalInput == entry.canonical || canonicalInput.hasPrefix(entry.canonical + "/") {
                return (entry.proj, true)
            }
        }

        // 2. Walk up to git root if inside an unregistered git repository (without probing TCC-protected Desktop/Documents/Downloads)
        var currentURL = URL(fileURLWithPath: canonicalInput, isDirectory: true)
        let homeStd = PathConstants.effectiveHomeDirectory.standardizedFileURL.path
        var stopPaths: Set<String> = [
            "/",
            homeStd,
            "\(homeStd)/Desktop",
            "\(homeStd)/Desktop/Projects",
            "\(homeStd)/Documents",
            "\(homeStd)/Downloads",
            "\(homeStd)/Projects",
            "\(homeStd)/Developer",
            "\(homeStd)/Code",
            "\(homeStd)/workspace"
        ]
        if let customProj = PathConstants.customProjectsDirectory?.resolvingSymlinksInPath().path {
            stopPaths.insert(customProj)
        } else if PathConstants.isRunningUnderTests || PathConstants.hasEnvironmentOverride {
            stopPaths.insert(PathConstants.defaultProjectsDirectory.resolvingSymlinksInPath().path)
        }
        if let authorizedRoot = ProjectFolderAccessManager.shared.authorizedDirectoryURL?.standardizedFileURL.path {
            stopPaths.insert(authorizedRoot)
        }
        var resolvedRootURL = currentURL
        while !stopPaths.contains(currentURL.path) {
            if fm.fileExists(atPath: currentURL.appendingPathComponent(".git").path)
                || fm.fileExists(atPath: currentURL.appendingPathComponent(".agents").path) {
                resolvedRootURL = currentURL
                break
            }
            let parent = currentURL.deletingLastPathComponent()
            if parent.path == currentURL.path { break }
            currentURL = parent
        }

        let name = resolvedRootURL.lastPathComponent.isEmpty ? "workspace" : resolvedRootURL.lastPathComponent
        let existingIds = Set(projects.map(\.id))
        let uniqueId: String
        if existingIds.contains(name) {
            let parentName = resolvedRootURL.deletingLastPathComponent().lastPathComponent
            let shortHash = PathConstants.stableShortHash(resolvedRootURL.path, length: 6)
            let candidate = parentName.isEmpty ? "\(name)-\(shortHash)" : "\(parentName)-\(name)"
            uniqueId = existingIds.contains(candidate) ? "\(name)-\(shortHash)" : candidate
        } else {
            uniqueId = name
        }
        var ephemeral = ProjectProfile(id: uniqueId, name: name, path: resolvedRootURL.path)

        // Inspect existing .agents/plugins and .agents/skills on disk
        let pluginsDir = resolvedRootURL.appendingPathComponent(".agents/plugins", isDirectory: true)
        if let pluginFolders = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) {
            for pluginFolder in pluginFolders where !pluginFolder.lastPathComponent.hasPrefix(".") {
                let pluginName = pluginFolder.lastPathComponent
                guard PathConstants.isSafeResourceId(pluginName) else { continue }
                if pluginName != "agy-manager" {
                    ephemeral.enabledPluginIds.insert(pluginName)
                }
                let mcpFile = pluginFolder.appendingPathComponent("mcp_config.json")
                if let data = try? Data(contentsOf: mcpFile),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let servers = json["mcpServers"] as? [String: Any] {
                    for key in servers.keys where PathConstants.isSafeResourceId(key) {
                        ephemeral.enabledMCPServerIds.insert(key)
                    }
                }
            }
        }

        let skillsDir = resolvedRootURL.appendingPathComponent(".agents/skills", isDirectory: true)
        if let skillFolders = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) {
            for skillFolder in skillFolders where !skillFolder.lastPathComponent.hasPrefix(".") {
                let skillName = skillFolder.lastPathComponent
                guard PathConstants.isSafeResourceId(skillName) else { continue }
                if (try? fm.destinationOfSymbolicLink(atPath: skillFolder.path)) != nil {
                    ephemeral.enabledSkillIds.insert(skillName)
                }
            }
        }

        return (ephemeral, false)
    }

    private static func notifyMenuBarApp(
        projectPath: String,
        projectId: String?,
        projectName: String?,
        source: String,
        didMutateVault: Bool
    ) {
        guard !PathConstants.isRunningUnderTests else { return }
        var userInfo: [String: String] = [
            "projectPath": projectPath,
            "source": source,
            "didMutateVault": didMutateVault ? "true" : "false"
        ]
        if let projectId { userInfo["projectId"] = projectId }
        if let projectName { userInfo["projectName"] = projectName }

        DistributedNotificationCenter.default().postNotificationName(
            PathConstants.contextDidChangeNotification,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    // MARK: - Output Formatting
    private static func formatBriefMarkdown(_ brief: CLIBriefResponse) -> String {
        var lines: [String] = []
        let proj = brief.project
        let stackText = proj.stackLabels.isEmpty ? "" : " (\(proj.stackLabels.joined(separator: ", ")))"
        lines.append("# 📦 Vault Brief: \(proj.name)\(stackText)")
        lines.append("Path: `\(proj.path)`")
        lines.append("")

        let pMCP = brief.active.projectMCPs.map(\.id)
        let gMCP = brief.active.globalMCPs.map(\.id)
        let pSkills = brief.active.projectSkills.map(\.id)
        let lSkills = brief.active.localSkills.map(\.id)
        let gSkills = brief.active.globalSkills.map(\.id)
        let pPlugins = brief.active.projectPlugins.map(\.id)
        let gPlugins = brief.active.globalPlugins.map(\.id)

        lines.append("## 1. Active in This Project")
        lines.append("- **Project MCP (\(pMCP.count)):** \(pMCP.isEmpty ? "none" : pMCP.joined(separator: ", "))")
        lines.append("- **Global MCP (\(gMCP.count)):** \(gMCP.isEmpty ? "none" : gMCP.joined(separator: ", "))")
        lines.append("- **Project Skills (\(pSkills.count)):** \(pSkills.isEmpty ? "none" : pSkills.joined(separator: ", "))")
        if !lSkills.isEmpty {
            lines.append("- **Local Repo Skills (\(lSkills.count)):** \(lSkills.joined(separator: ", "))")
        }
        lines.append("- **Global Skills (\(gSkills.count)):** \(gSkills.isEmpty ? "none" : gSkills.joined(separator: ", "))")
        if !pPlugins.isEmpty || !gPlugins.isEmpty {
            let allPlug = (pPlugins.map { "\($0) (proj)" } + gPlugins.map { "\($0) (global)" }).joined(separator: ", ")
            lines.append("- **Plugins:** \(allPlug)")
        }
        lines.append("")

        lines.append("## 2. Recommended from Vault (\(brief.recommendations.count))")
        if brief.recommendations.isEmpty {
            lines.append("- All recognized recommendations for this stack are already active.")
        } else {
            for rec in brief.recommendations {
                lines.append("- **[\(rec.kind.displayLabel)] `\(rec.id)`** — \(rec.reason)")
            }
        }
        lines.append("")

        lines.append("## 3. Available in Vault Catalog (on demand)")
        let inMCP = brief.vaultCatalog.inactiveMCPs.map(\.id)
        let inSkills = brief.vaultCatalog.inactiveSkills.map(\.id)
        let inPlugins = brief.vaultCatalog.inactivePlugins.map(\.id)
        lines.append("- **Other MCP (\(inMCP.count)):** \(inMCP.isEmpty ? "none" : inMCP.joined(separator: ", "))")
        lines.append("- **Other Skills (\(inSkills.count)):** \(inSkills.isEmpty ? "none" : inSkills.joined(separator: ", "))")
        lines.append("- **Other Plugins (\(inPlugins.count)):** \(inPlugins.isEmpty ? "none" : inPlugins.joined(separator: ", "))")

        return lines.joined(separator: "\n")
    }

    private static func buildSetSummaryMessage(
        targetName: String,
        enabledMCP: [String],
        disabledMCP: [String],
        enabledSkill: [String],
        disabledSkill: [String],
        enabledPlugin: [String],
        disabledPlugin: [String],
        unknownIds: [String],
        requiresReload: Bool
    ) -> String {
        var parts: [String] = []
        if !enabledMCP.isEmpty { parts.append("+MCP: \(enabledMCP.joined(separator: ", "))") }
        if !disabledMCP.isEmpty { parts.append("-MCP: \(disabledMCP.joined(separator: ", "))") }
        if !enabledSkill.isEmpty { parts.append("+Skill: \(enabledSkill.joined(separator: ", "))") }
        if !disabledSkill.isEmpty { parts.append("-Skill: \(disabledSkill.joined(separator: ", "))") }
        if !enabledPlugin.isEmpty { parts.append("+Plugin: \(enabledPlugin.joined(separator: ", "))") }
        if !disabledPlugin.isEmpty { parts.append("-Plugin: \(disabledPlugin.joined(separator: ", "))") }

        var msg = "Synchronized '\(targetName)': \(parts.joined(separator: " | "))."
        if !unknownIds.isEmpty {
            msg += " Unknown IDs in Vault: \(unknownIds.joined(separator: ", "))."
        }
        if requiresReload {
            msg += " Note: MCP server changes require a session reload or new chat, while skills are active immediately."
        }
        return msg
    }

    private static func formatSetOutput(_ response: CLISetResponse, asJSON: Bool) -> CLIExecutionResult {
        if asJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(response),
               let str = String(data: data, encoding: .utf8) {
                return CLIExecutionResult(exitCode: 0, stdout: str)
            }
        }
        return CLIExecutionResult(exitCode: 0, stdout: response.message)
    }

    private static func buildUserRadarMarkdown(_ brief: CLIBriefResponse) -> String {
        let globalMCPIdSet = Set(brief.active.globalMCPs.map(\.id))
        let projMCPIds = brief.active.projectMCPs.map(\.id).filter { !globalMCPIdSet.contains($0) }.sorted()
        let globalMCPCount = globalMCPIdSet.count

        let globalSkillIdSet = Set(brief.active.globalSkills.map(\.id))
        let projSkillIds = Set(brief.active.projectSkills.map(\.id))
            .union(brief.active.localSkills.map(\.id))
            .subtracting(globalSkillIdSet)
            .sorted()
        let globalSkillCount = globalSkillIdSet.count
        let projPluginIds = brief.active.projectPlugins.map(\.id).sorted()

        let stackBadge = brief.project.stackLabels.isEmpty
            ? ""
            : " (\(brief.project.stackLabels.joined(separator: ", ")))"

        let mcpPart: String
        if projMCPIds.isEmpty {
            mcpPart = "MCP: \(globalMCPCount) global"
        } else {
            mcpPart = "MCP: \(projMCPIds.joined(separator: ", ")) (+\(globalMCPCount) global)"
        }

        let skillsPart: String
        if projSkillIds.isEmpty {
            skillsPart = "Skills: \(globalSkillCount) global"
        } else if projSkillIds.count <= 3 {
            skillsPart = "Skills: \(projSkillIds.joined(separator: ", ")) (+\(globalSkillCount) global)"
        } else {
            skillsPart = "Skills: \(projSkillIds.count) proj (+\(globalSkillCount) global)"
        }

        var line1 = "> 📦 **\(brief.project.name)**\(stackBadge) · \(mcpPart) · \(skillsPart)"
        if !projPluginIds.isEmpty {
            line1 += " · Plugins: \(projPluginIds.joined(separator: ", "))"
        }

        let line2: String
        if !brief.recommendations.isEmpty {
            let topRecs = brief.recommendations.prefix(3).map { "`\($0.id)`" }.joined(separator: ", ")
            let stackContext = brief.project.stackLabels.isEmpty
                ? "recognized tools for this repo"
                : "detected \(brief.project.stackLabels.joined(separator: " + "))"
            line2 = "> 💡 **Vault Suggestion:** \(stackContext) (suggested: \(topRecs)) — type `/vault` to configure."
        } else if brief.project.isEmptyProjectSetup {
            let emptyDesc = brief.project.stackLabels.isEmpty
                ? "no project-scoped MCPs or skills enabled yet — type `/vault` to browse the catalog."
                : "detected \(brief.project.stackLabels.joined(separator: " + ")) project (0 active project MCPs/skills) — type `/vault` to configure."
            line2 = "> 💡 **Vault Suggestion:** \(emptyDesc)"
        } else {
            let stackText = brief.project.stackLabels.isEmpty
                ? "this repo"
                : brief.project.stackLabels.joined(separator: " + ")
            line2 = "> ✅ **Vault Radar:** All recommended tools for \(stackText) are active — type `/vault` to customize."
        }

        return "\(line1)\n\(line2)"
    }

    private static func buildModelRadarSystemMessage(_ brief: CLIBriefResponse) -> String {
        let userMarkdown = buildUserRadarMarkdown(brief)
        let pMCP = brief.active.projectMCPs.map(\.id).joined(separator: ",")
        let gMCP = brief.active.globalMCPs.map(\.id).joined(separator: ",")
        let pSkills = (brief.active.projectSkills.map(\.id) + brief.active.localSkills.map(\.id)).joined(separator: ",")
        let pPlugins = brief.active.projectPlugins.map(\.id).joined(separator: ",")
        let recs = brief.recommendations.map { "\($0.kind.rawValue):\($0.id)" }.joined(separator: ",")
        let inMCP = brief.vaultCatalog.inactiveMCPs.map(\.id).joined(separator: ",")
        let inSkills = brief.vaultCatalog.inactiveSkills.map(\.id).joined(separator: ",")
        let inPlugins = brief.vaultCatalog.inactivePlugins.map(\.id).joined(separator: ",")

        return """
        [agymg Vault Radar | project=\(brief.project.name) (\(brief.project.path))]
        MANDATORY FIRST-TURN UI BANNER (CRITICAL):
        Because Antigravity collapses SessionStart hook steps inside the 'Worked for Xs' group, the user cannot see this hook step directly.
        Therefore, at the VERY TOP of your response to this turn (before your greeting or answer, even if the user only said "hi" or "hello"), you MUST output the following 2-line Vault Radar blockquote verbatim, followed by a blank line (this is an explicit UI feature configured by the user and does NOT violate any brevity or no-fluff rule; only skip it if the user's message is literally `/vault`, in which case output the full `/vault` report):

        \(userMarkdown)

        Active Project MCPs: [\(pMCP)] | Global MCPs: [\(gMCP)] | Project Skills: [\(pSkills)] | Project Plugins: [\(pPlugins)]
        Recommended for repo: [\(recs)]
        Inactive Vault Catalog -> MCPs: [\(inMCP)] | Skills: [\(inSkills)] | Plugins: [\(inPlugins)]
        Proactive Rule: If the user triggers /vault, asks about active/available MCPs/skills/plugins, or works on a task covered by an inactive Vault resource, proactively suggest it or run `agymg brief --project "\(brief.project.path)" --json` and `agymg set --project "\(brief.project.path)" --enable-mcp <id> --enable-skill <id> --enable-plugin <id>`.
        """
    }

    private static func formatAntigravitySessionStartJSON(_ brief: CLIBriefResponse) -> String {
        let systemMsg = buildModelRadarSystemMessage(brief)

        // Note: Do NOT include HookSystemMessage.metadata map<string, string> here;
        // Antigravity 2.0's utils.ScrubInternalFields (proto_utils.go:34) panics with
        // "type mismatch: cannot convert string to message" when iterating map<string, string>.
        let payload: [String: Any] = [
            "injectSteps": [
                [
                    "systemMessage": [
                        "systemMessage": systemMsg
                    ]
                ]
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private static func formatClaudeSessionStartText(_ brief: CLIBriefResponse) -> String {
        let systemMsg = buildModelRadarSystemMessage(brief)
        return "# Antigravity Vault Radar\n\n\(systemMsg)"
    }

    public static let helpText = """
    agymg — Proactive Antigravity & Claude Code Control Center CLI

    USAGE:
      agymg brief [--project <path>] [--json]
      agymg set [--project <path> | --global] [options] [--json]
      agymg hook-session-start [--format antigravity|claude-text] [--project <path>]
      agymg install-app [--dest <dir>] [--source <path>]
      agymg uninstall --restore [--purge-vault] [--json]
      agymg --version

    OPTIONS FOR 'set':
      --project <path>         Target project directory (defaults to current directory)
      --global                 Apply changes to Global Core instead of a project
      --enable-mcp <ids>       Comma-separated MCP server IDs to enable
      --disable-mcp <ids>      Comma-separated MCP server IDs to disable
      --enable-skill <ids>     Comma-separated Vault skill IDs to enable
      --disable-skill <ids>    Comma-separated Vault skill IDs to disable
      --enable-plugin <ids>    Comma-separated Vault plugin IDs to enable
      --disable-plugin <ids>   Comma-separated Vault plugin IDs to disable
      --json                   Output structured JSON response

    OPTIONS FOR 'uninstall':
      --restore                Restore symlinked skills/plugins to standalone directories and clean wrappers/hooks
      --purge-vault            Also delete ~/.gemini/manager-vault (including configuration backups)
      --json                   Output structured JSON summary
    """
}
