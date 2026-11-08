import Foundation

extension SyncEngine {
    // MARK: - Project Sync
    public func syncProject(
        project: ProjectProfile,
        allServers: [MCPServerDefinition],
        allSkills: [SkillDefinition],
        allPlugins: [PluginDefinition]
    ) throws {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project.path)
        guard fm.fileExists(atPath: projectURL.path) else { return }

        _ = createConfigSnapshotIfNeeded(force: false)

        let agentsDir = projectURL.appendingPathComponent(".agents", isDirectory: true)

        // 1. Sync Project MCP Servers (via .agents/plugins/agy-manager)
        let pluginDir = agentsDir.appendingPathComponent("plugins/agy-manager", isDirectory: true)
        let validServerIds = project.enabledMCPServerIds.filter { PathConstants.isSafeResourceId($0) }
        if validServerIds.isEmpty {
            if fm.fileExists(atPath: pluginDir.path) || isSymlink(at: pluginDir) {
                try? fm.removeItem(at: pluginDir)
            }
        } else {
            // Only protect .gitignore when this is a git repository AND agymg is writing project MCP configs
            if fm.fileExists(atPath: projectURL.appendingPathComponent(".git").path) {
                ensureGitignore(at: projectURL)
            }

            try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

            let pluginJsonURL = pluginDir.appendingPathComponent("plugin.json")
            let pluginMeta: [String: Any] = ["name": "agy-manager"]
            let metaData = try JSONSerialization.data(withJSONObject: pluginMeta, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try metaData.write(to: pluginJsonURL, options: .atomic)

            let serverMap = Dictionary(uniqueKeysWithValues: allServers.map { ($0.id, $0) })
            var projectServers: [String: [String: Any]] = [:]

            for serverId in validServerIds {
                if let server = serverMap[serverId] {
                    var raw = server.config.mapValues { $0.toAny() }
                    raw.removeValue(forKey: "disabled")
                    projectServers[serverId] = raw
                }
            }

            let mcpConfigURL = pluginDir.appendingPathComponent("mcp_config.json")
            let mcpPayload: [String: Any] = ["mcpServers": projectServers]
            let mcpData = try JSONSerialization.data(withJSONObject: mcpPayload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try PathConstants.writeSecureData(mcpData, to: mcpConfigURL, permissions: 0o600)
        }

        // 2. Sync Project Skills (via .agents/skills/<skill-id>)
        let projectSkillsDir = agentsDir.appendingPathComponent("skills", isDirectory: true)
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory

        if !project.enabledSkillIds.isEmpty {
            try fm.createDirectory(at: projectSkillsDir, withIntermediateDirectories: true)
        }

        for skill in allSkills where PathConstants.isSafeResourceId(skill.id) {
            let targetURL = projectSkillsDir.appendingPathComponent(skill.id)
            let vaultSkillURL = vaultSkillsDir.appendingPathComponent(skill.id)
            let sourceURL = fm.fileExists(atPath: vaultSkillURL.path)
                ? vaultSkillURL
                : URL(fileURLWithPath: skill.path)

            if project.enabledSkillIds.contains(skill.id) {
                if isSymlink(at: targetURL) {
                    let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                    if symlinkDest != sourceURL.path {
                        try? fm.removeItem(at: targetURL)
                        if fm.fileExists(atPath: sourceURL.path) {
                            try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                        }
                    }
                } else if !fm.fileExists(atPath: targetURL.path) {
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                    }
                }
            } else {
                if isSymlink(at: targetURL) {
                    try? fm.removeItem(at: targetURL)
                }
            }
        }

        // 3. Sync Project Plugins (via .agents/plugins/<plugin-id>)
        let projectPluginsDir = agentsDir.appendingPathComponent("plugins", isDirectory: true)
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory

        for plugin in allPlugins where PathConstants.isSafeResourceId(plugin.id) {
            guard plugin.id != "agy-manager" else { continue }
            let targetURL = projectPluginsDir.appendingPathComponent(plugin.id)
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourceURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)

            if project.enabledPluginIds.contains(plugin.id) {
                if targetURL.resolvingSymlinksInPath().path == sourceURL.resolvingSymlinksInPath().path && !isSymlink(at: targetURL) {
                    continue
                }
                try fm.createDirectory(at: projectPluginsDir, withIntermediateDirectories: true)
                if isSymlink(at: targetURL) {
                    let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                    if symlinkDest != sourceURL.path {
                        try? fm.removeItem(at: targetURL)
                        if fm.fileExists(atPath: sourceURL.path) {
                            try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                        }
                    }
                } else if !fm.fileExists(atPath: targetURL.path) {
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                    }
                }
            } else {
                if isSymlink(at: targetURL) {
                    try? fm.removeItem(at: targetURL)
                } else if fm.fileExists(atPath: targetURL.path),
                          !fm.fileExists(atPath: vaultPluginURL.path),
                          !isGitTrackedPath(targetURL, in: projectURL) {
                    try? fm.createDirectory(at: vaultPluginsDir, withIntermediateDirectories: true)
                    if (try? fm.copyItem(at: targetURL, to: vaultPluginURL)) != nil {
                        try? fm.removeItem(at: targetURL)
                    }
                }
            }
        }

        // 4. Sync Project MCP Servers to Claude (~/.claude.json -> projects[project.path].mcpServers)
        syncClaudeProjectMCP(project: project, allServers: allServers, allPlugins: allPlugins)

        // 5. Sync Project Skills & Plugin Skills to Claude (<project>/.claude/skills/<skill-id>)
        syncClaudeProjectSkills(project: project, allSkills: allSkills, allPlugins: allPlugins)
    }

    private func isGitTrackedPath(_ targetURL: URL, in projectURL: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectURL.appendingPathComponent(".git").path) else {
            return false
        }
        let repoStd = projectURL.standardizedFileURL.path
        let targetStd = targetURL.standardizedFileURL.path
        guard targetStd.hasPrefix(repoStd + "/") else { return false }
        let relativePath = String(targetStd.dropFirst(repoStd.count + 1))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoStd, "ls-files", "--", relativePath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return true }
            let text = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !text.isEmpty
        } catch {
            return true
        }
    }

    public func syncClaudeProjectSkills(
        project: ProjectProfile,
        allSkills: [SkillDefinition],
        allPlugins: [PluginDefinition]
    ) {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project.path)
        let vaultSkillsDir = PathConstants.vaultSkillsDirectory
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory

        var desiredSkillSources: [String: URL] = [:]

        // 1. Enabled Vault / Global skills for this project
        for skill in allSkills where PathConstants.isSafeResourceId(skill.id) && project.enabledSkillIds.contains(skill.id) {
            let vaultSkillURL = vaultSkillsDir.appendingPathComponent(skill.id)
            let sourceURL = fm.fileExists(atPath: vaultSkillURL.path)
                ? vaultSkillURL
                : URL(fileURLWithPath: skill.path)
            if fm.fileExists(atPath: sourceURL.path) {
                desiredSkillSources[skill.id] = sourceURL
            }
        }

        // 2. Local project skills in <project>/.agents/skills/
        let agentsSkillsDir = projectURL.appendingPathComponent(".agents/skills", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: agentsSkillsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items {
                let skillId = item.lastPathComponent
                guard PathConstants.isSafeResourceId(skillId) else { continue }
                if desiredSkillSources[skillId] == nil && fm.fileExists(atPath: item.path) {
                    desiredSkillSources[skillId] = item.resolvingSymlinksInPath()
                }
            }
        }

        // 3. Skills bundled inside enabled project plugins (<plugin>/skills/*)
        for plugin in allPlugins where PathConstants.isSafeResourceId(plugin.id) && project.enabledPluginIds.contains(plugin.id) && plugin.id != "agy-manager" {
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourcePluginURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)
            let pluginSkillsDir = sourcePluginURL.appendingPathComponent("skills", isDirectory: true)
            if let subSkills = try? fm.contentsOfDirectory(at: pluginSkillsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for subSkill in subSkills where fm.fileExists(atPath: subSkill.path) {
                    let subId = subSkill.lastPathComponent
                    guard PathConstants.isSafeResourceId(subId) else { continue }
                    if desiredSkillSources[subId] == nil {
                        desiredSkillSources[subId] = subSkill.resolvingSymlinksInPath()
                    }
                }
            }
        }

        let claudeSkillsDir = projectURL.appendingPathComponent(".claude/skills", isDirectory: true)

        // Clean up any stale symlinks in <project>/.claude/skills/ that are no longer enabled (never delete real directories)
        if let existingItems = try? fm.contentsOfDirectory(at: claudeSkillsDir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for item in existingItems {
                let name = item.lastPathComponent
                if desiredSkillSources[name] == nil && isSymlink(at: item) {
                    try? fm.removeItem(at: item)
                }
            }
        }

        guard !desiredSkillSources.isEmpty else { return }

        try? fm.createDirectory(at: claudeSkillsDir, withIntermediateDirectories: true)
        var createdSymlinkNames: [String] = []

        for (skillId, sourceURL) in desiredSkillSources where PathConstants.isSafeResourceId(skillId) {
            let targetURL = claudeSkillsDir.appendingPathComponent(skillId)
            if isSymlink(at: targetURL) {
                let symlinkDest = try? fm.destinationOfSymbolicLink(atPath: targetURL.path)
                if symlinkDest != sourceURL.path {
                    try? fm.removeItem(at: targetURL)
                    try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                }
                createdSymlinkNames.append(skillId)
            } else if !fm.fileExists(atPath: targetURL.path) {
                try? fm.createSymbolicLink(at: targetURL, withDestinationURL: sourceURL)
                createdSymlinkNames.append(skillId)
            }
        }

        // Ensure local .git/info/exclude hides symlinked .claude/skills entries so git status stays 100% clean without touching .gitignore
        ensureGitExcludeForSkills(at: projectURL, directory: ".claude/skills", symlinkedSkillIds: createdSymlinkNames)
    }

    /// A skill created in <project>/.claude/skills is a real folder, often committed, so it stays there:
    /// a symlink in .agents/skills is enough for Antigravity to see it.
    public func linkClaudeProjectSkills(project: ProjectProfile) {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project.path)
        let claudeSkillsDir = projectURL.appendingPathComponent(".claude/skills", isDirectory: true)
        let agentsSkillsDir = projectURL.appendingPathComponent(".agents/skills", isDirectory: true)
        // No .skipsHiddenFiles: it also drops folders with the macOS `hidden` flag, which project folders here carry.
        guard let items = try? fm.contentsOfDirectory(at: claudeSkillsDir, includingPropertiesForKeys: nil) else { return }

        var linkedSkillIds: [String] = []
        for item in items where !isSymlink(at: item) && fm.fileExists(atPath: item.appendingPathComponent("SKILL.md").path) {
            let skillId = item.lastPathComponent
            guard PathConstants.isSafeResourceId(skillId) else { continue }
            let targetURL = agentsSkillsDir.appendingPathComponent(skillId)
            guard !fm.fileExists(atPath: targetURL.path), !isSymlink(at: targetURL) else { continue }
            try? fm.createDirectory(at: agentsSkillsDir, withIntermediateDirectories: true)
            if (try? fm.createSymbolicLink(at: targetURL, withDestinationURL: item)) != nil {
                linkedSkillIds.append(skillId)
            }
        }
        ensureGitExcludeForSkills(at: projectURL, directory: ".agents/skills", symlinkedSkillIds: linkedSkillIds)
    }

    private func ensureGitExcludeForSkills(at projectURL: URL, directory: String, symlinkedSkillIds: [String]) {
        let fm = FileManager.default
        let gitExcludeURL = projectURL.appendingPathComponent(".git/info/exclude")
        guard fm.fileExists(atPath: gitExcludeURL.deletingLastPathComponent().path) else { return }

        let existingContent = (try? String(contentsOf: gitExcludeURL, encoding: .utf8)) ?? ""
        let existingLines = Set(existingContent.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) })

        let rootDirectory = String(directory.prefix { $0 != "/" })
        var linesToAdd: [String] = []
        for skillId in symlinkedSkillIds.sorted() {
            let entry = "\(directory)/\(skillId)"
            if !existingLines.contains(entry) && !existingLines.contains("\(rootDirectory)/") && !existingLines.contains(rootDirectory) {
                linesToAdd.append(entry)
            }
        }

        guard !linesToAdd.isEmpty else { return }
        var updated = existingContent
        if !updated.isEmpty && !updated.hasSuffix("\n") {
            updated += "\n"
        }
        updated += linesToAdd.joined(separator: "\n") + "\n"
        try? updated.write(to: gitExcludeURL, atomically: true, encoding: .utf8)
    }

    public func syncClaudeProjectMCP(
        project: ProjectProfile,
        allServers: [MCPServerDefinition],
        allPlugins: [PluginDefinition]
    ) {
        let fm = FileManager.default
        let oauthURLs = loadOAuthServerURLs()
        var oauthBackedIds: Set<String> = []
        let serverMap = Dictionary(uniqueKeysWithValues: allServers.map { ($0.id, $0) })
        var claudeProjectServers: [String: [String: Any]] = [:]

        for serverId in project.enabledMCPServerIds where PathConstants.isSafeResourceId(serverId) {
            if let server = serverMap[serverId] {
                let raw = server.config.mapValues { $0.toAny() }
                let converted = convertToClaudeMCPConfig(raw, oauthServerURLs: oauthURLs)
                if converted["headersHelper"] != nil {
                    oauthBackedIds.insert(serverId)
                }
                claudeProjectServers[serverId] = converted
            }
        }

        // Include MCP servers bundled inside enabled project plugins
        let vaultPluginsDir = PathConstants.vaultPluginsDirectory
        for plugin in allPlugins where PathConstants.isSafeResourceId(plugin.id) && project.enabledPluginIds.contains(plugin.id) && plugin.id != "agy-manager" {
            let vaultPluginURL = vaultPluginsDir.appendingPathComponent(plugin.id)
            let sourcePluginURL = fm.fileExists(atPath: vaultPluginURL.path)
                ? vaultPluginURL
                : URL(fileURLWithPath: plugin.path)
            let pluginMCPFile = sourcePluginURL.appendingPathComponent("mcp_config.json")
            if let data = try? Data(contentsOf: pluginMCPFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pluginServers = json["mcpServers"] as? [String: [String: Any]] {
                for (serverId, rawConfig) in pluginServers where PathConstants.isSafeResourceId(serverId) {
                    guard claudeProjectServers[serverId] == nil else { continue }
                    let converted: [String: Any]
                    if let vaultServer = serverMap[serverId] {
                        let raw = vaultServer.config.mapValues { $0.toAny() }
                        converted = convertToClaudeMCPConfig(raw, oauthServerURLs: oauthURLs)
                    } else {
                        converted = convertToClaudeMCPConfig(rawConfig, oauthServerURLs: oauthURLs)
                    }
                    if converted["headersHelper"] != nil {
                        oauthBackedIds.insert(serverId)
                    }
                    claudeProjectServers[serverId] = converted
                }
            }
        }

        if !oauthBackedIds.isEmpty {
            ensureClaudeEnvironment()
            clearStaleNeedsAuthCache(forServerIds: oauthBackedIds)
        }

        for configFile in PathConstants.allClaudeConfigFiles {
            let claudeConfigURL = configFile.resolvingSymlinksInPath()
            var rootDict: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: claudeConfigURL),
               let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                rootDict = existingJSON
            }

            var projectsDict = (rootDict["projects"] as? [String: Any]) ?? [:]
            let existingEntry = projectsDict[project.path] as? [String: Any]
            let existingServers = existingEntry?["mcpServers"] as? [String: Any]

            if claudeProjectServers.isEmpty && (existingServers == nil || existingServers?.isEmpty == true) {
                continue
            }

            var projectEntry = existingEntry ?? [:]
            // Claude Code writes this file constantly, so touch it only when mcpServers actually changed.
            guard (projectEntry["mcpServers"] as? NSDictionary) != (claudeProjectServers as NSDictionary) else { continue }
            projectEntry["mcpServers"] = claudeProjectServers
            projectsDict[project.path] = projectEntry
            rootDict["projects"] = projectsDict

            if let data = try? JSONSerialization.data(withJSONObject: rootDict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? PathConstants.writeSecureData(data, to: claudeConfigURL, permissions: 0o600, preserveExistingPermissions: true)
            }
        }
    }

    public func isSymlink(at url: URL) -> Bool {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return true
        }
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink == true
    }

    public func ensureGitignore(at projectURL: URL) {
        let fm = FileManager.default
        let gitignoreURL = projectURL.appendingPathComponent(".gitignore")
        let protectionBlock = """
# Antigravity local agent configurations & MCP tokens
.agents/plugins/agy-manager/
.agents/mcp_config.json
"""

        if fm.fileExists(atPath: gitignoreURL.path) {
            guard let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) else { return }

            let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            let alreadyProtected = lines.contains { rawLine in
                let line = rawLine.hasPrefix("/") ? String(rawLine.dropFirst()) : rawLine
                return line == ".agents" || line == ".agents/" || line == ".agents/*"
                    || line == ".agents/plugins" || line == ".agents/plugins/" || line == ".agents/plugins/*"
                    || line == ".agents/plugins/agy-manager" || line == ".agents/plugins/agy-manager/" || line == ".agents/plugins/agy-manager/*"
            }

            if alreadyProtected {
                return
            }

            let updated: String
            if content.hasSuffix("\n") {
                updated = content + protectionBlock + "\n"
            } else {
                updated = content + "\n\n" + protectionBlock + "\n"
            }
            try? updated.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        } else {
            let initialContent = protectionBlock + "\n"
            try? initialContent.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        }
    }

    public static let mcpOAuthHeadersScriptContent = #"""
#!/usr/bin/env python3
import base64
from datetime import datetime, timedelta, timezone
import fcntl
import json
import os
import pwd
import sys
import time
import urllib.parse
import urllib.request

REFRESH_BUFFER_SECONDS = 300


def get_real_home() -> str:
    try:
        return os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)
    except Exception:
        return os.path.realpath(os.path.expanduser("~"))


def get_jwt_exp(token: str):
    parts = token.split(".")
    if len(parts) != 3:
        return None
    try:
        padded = parts[1] + "=" * (-len(parts[1]) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))
        exp = payload.get("exp")
        return float(exp) if exp is not None else None
    except Exception:
        return None


def get_iso_exp(expiry_str: str):
    if not expiry_str or not isinstance(expiry_str, str):
        return None
    try:
        normalized = expiry_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)
        return dt.timestamp()
    except Exception:
        return None


def is_token_expiring(token_obj: dict, buffer_sec: int = REFRESH_BUFFER_SECONDS) -> bool:
    access_token = token_obj.get("access_token")
    if not access_token or not isinstance(access_token, str):
        return True

    now = time.time()
    jwt_exp = get_jwt_exp(access_token)
    if jwt_exp is not None:
        return (jwt_exp - now) <= buffer_sec

    iso_exp = get_iso_exp(token_obj.get("expiry", ""))
    if iso_exp is not None:
        return (iso_exp - now) <= buffer_sec

    return False


def find_entry_key(data: dict, target_url: str):
    if target_url in data:
        return target_url
    norm = target_url.rstrip("/")
    for k in data.keys():
        if k.rstrip("/") == norm:
            return k
    return None


def refresh_oauth_token(entry: dict):
    token_obj = entry.get("token") or {}
    refresh_token = token_obj.get("refresh_token")
    token_url = entry.get("token_url")
    client_id = entry.get("client_id")

    if not refresh_token or not token_url:
        return None

    form_data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    }
    if client_id:
        form_data["client_id"] = client_id

    body = urllib.parse.urlencode(form_data).encode("utf-8")
    req = urllib.request.Request(
        token_url,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            "User-Agent": "antigravity-mcp-oauth-helper/1.0",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=8) as resp:
        resp_data = json.loads(resp.read().decode("utf-8"))

    new_access = resp_data.get("access_token")
    if not new_access:
        return None

    updated_token = dict(token_obj)
    updated_token["access_token"] = new_access
    if resp_data.get("refresh_token"):
        updated_token["refresh_token"] = resp_data["refresh_token"]
    if resp_data.get("token_type"):
        updated_token["token_type"] = resp_data["token_type"]

    expires_in = resp_data.get("expires_in")
    exp_ts = None
    if isinstance(expires_in, (int, float)) and expires_in > 0:
        exp_ts = time.time() + float(expires_in)
    else:
        exp_ts = get_jwt_exp(new_access)

    if exp_ts is not None:
        local_dt = datetime.fromtimestamp(exp_ts, tz=timezone.utc).astimezone()
        updated_token["expiry"] = local_dt.isoformat()

    return updated_token


def clear_claude_needs_auth_cache(real_home: str, server_name: str):
    if not server_name:
        return
    cache_paths = [
        os.path.join(real_home, ".claude", "mcp-needs-auth-cache.json"),
    ]
    profiles_root = os.path.join(real_home, "AntigravityProfiles")
    if os.path.isdir(profiles_root):
        try:
            for name in os.listdir(profiles_root):
                if name.startswith("Profile"):
                    cache_paths.append(
                        os.path.join(profiles_root, name, "home", ".claude", "mcp-needs-auth-cache.json")
                    )
        except Exception:
            pass

    for cpath in cache_paths:
        if not os.path.isfile(cpath):
            continue
        try:
            with open(cpath, "r", encoding="utf-8") as f:
                cache_data = json.load(f)
            if isinstance(cache_data, dict) and server_name in cache_data:
                del cache_data[server_name]
                tmp_path = cpath + ".tmp"
                with open(tmp_path, "w", encoding="utf-8") as f:
                    json.dump(cache_data, f)
                os.replace(tmp_path, cpath)
        except Exception:
            pass


def load_static_headers_fallback(real_home: str, server_url: str, server_name: str) -> dict:
    norm_url = server_url.rstrip("/")
    config_file = os.path.join(real_home, ".gemini", "config", "mcp_config.json")
    if os.path.isfile(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            servers = cfg.get("mcpServers") if isinstance(cfg, dict) else {}
            if isinstance(servers, dict):
                for sid, sdict in servers.items():
                    if not isinstance(sdict, dict):
                        continue
                    surl = (sdict.get("serverUrl") or sdict.get("url") or "").rstrip("/")
                    if (server_name and sid == server_name) or (norm_url and surl == norm_url):
                        hdrs = sdict.get("headers")
                        if isinstance(hdrs, dict) and hdrs:
                            return {str(k): str(v) for k, v in hdrs.items() if v}
        except Exception:
            pass

    vault_file = os.path.join(real_home, ".gemini", "manager-vault", "master_mcp.json")
    if os.path.isfile(vault_file):
        try:
            with open(vault_file, "r", encoding="utf-8") as f:
                vault_list = json.load(f)
            if isinstance(vault_list, list):
                for item in vault_list:
                    if not isinstance(item, dict):
                        continue
                    sid = item.get("id", "")
                    sdict = item.get("config") if isinstance(item.get("config"), dict) else {}
                    surl = (sdict.get("serverUrl") or sdict.get("url") or "").rstrip("/")
                    if (server_name and sid == server_name) or (norm_url and surl == norm_url):
                        hdrs = sdict.get("headers")
                        if isinstance(hdrs, dict) and hdrs:
                            return {str(k): str(v) for k, v in hdrs.items() if v}
        except Exception:
            pass

    return {}


def main():
    server_url = os.environ.get("CLAUDE_CODE_MCP_SERVER_URL", "").strip()
    server_name = os.environ.get("CLAUDE_CODE_MCP_SERVER_NAME", "").strip()
    if not server_url and len(sys.argv) > 1:
        server_url = sys.argv[1].strip()

    if not server_url:
        sys.stdout.write("{}\n")
        return

    real_home = get_real_home()
    custom_oauth = os.environ.get("CLAUDE_CODE_MCP_OAUTH_FILE", "").strip()
    oauth_file = (
        os.path.realpath(custom_oauth)
        if custom_oauth
        else os.path.realpath(os.path.join(real_home, ".gemini", "antigravity", "mcp_oauth_tokens.json"))
    )

    fallback_headers = load_static_headers_fallback(real_home, server_url, server_name)
    if any(k.lower() == "authorization" for k in fallback_headers.keys()):
        sys.stdout.write(json.dumps(fallback_headers) + "\n")
        return

    data = {}
    if os.path.isfile(oauth_file):
        try:
            with open(oauth_file, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
        except Exception:
            data = {}

    key = find_entry_key(data, server_url)
    if key and isinstance(data.get(key), dict):
        entry = data[key]
        token_obj = entry.get("token") if isinstance(entry.get("token"), dict) else {}

        if is_token_expiring(token_obj):
            lock_path = os.path.join(os.path.dirname(oauth_file), ".mcp_oauth_tokens.lock")
            try:
                with open(lock_path, "w") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    try:
                        with open(oauth_file, "r", encoding="utf-8") as f:
                            fresh_data = json.load(f)
                        fresh_entry = fresh_data.get(key, entry)
                        fresh_tok = fresh_entry.get("token") if isinstance(fresh_entry.get("token"), dict) else {}
                        if is_token_expiring(fresh_tok):
                            refreshed = refresh_oauth_token(fresh_entry)
                            if refreshed:
                                fresh_entry["token"] = refreshed
                                fresh_data[key] = fresh_entry
                                tmp_file = oauth_file + ".tmp"
                                fd = os.open(tmp_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                                with os.fdopen(fd, "w", encoding="utf-8") as wf:
                                    json.dump(fresh_data, wf, indent=2)
                                os.chmod(tmp_file, 0o600)
                                os.replace(tmp_file, oauth_file)
                                token_obj = refreshed
                            else:
                                token_obj = fresh_tok
                        else:
                            token_obj = fresh_tok
                    finally:
                        fcntl.flock(lock_f, fcntl.LOCK_UN)
            except Exception:
                pass

        access_token = token_obj.get("access_token", "")
        if access_token:
            clear_claude_needs_auth_cache(real_home, server_name)
            sys.stdout.write(json.dumps({"Authorization": f"Bearer {access_token}"}) + "\n")
            return

    if fallback_headers:
        sys.stdout.write(json.dumps(fallback_headers) + "\n")
    else:
        sys.stdout.write("{}\n")


if __name__ == "__main__":
    main()
"""#
}

