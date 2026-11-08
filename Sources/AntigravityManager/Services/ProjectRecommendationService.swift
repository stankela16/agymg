import Foundation

public struct ProjectStackInspection: Sendable {
    public var hasSwiftPackage: Bool = false
    public var hasXcodeProject: Bool = false
    public var isMacOSTarget: Bool = false
    public var isIOSTarget: Bool = false
    public var hasPackageJson: Bool = false
    public var npmDependencies: Set<String> = []
    public var hasSupabaseMarker: Bool = false
    public var hasPostHogMarker: Bool = false
    public var hasPolarMarker: Bool = false
    public var hasShadcnMarker: Bool = false
    public var hasWebFrontendMarker: Bool = false
    public var hasRemotionMarker: Bool = false
    public var hasVercelMarker: Bool = false
    public var hasNetlifyMarker: Bool = false
    public var hasTelegramMarker: Bool = false
    public var hasBrevoMarker: Bool = false
    public var hasAWSMarker: Bool = false
    public var hasDockerOrVPSMarker: Bool = false
    public var hasGCloudMarker: Bool = false
    public var hasDigitalOceanMarker: Bool = false
    public var hasAuthOrDatabaseMarker: Bool = false
    public var stackLabels: [String] = []

    public init() {}
}

public struct ProjectRecommendationService: Sendable {
    public init() {}

    public static func isNonProjectContainerRoot(_ rawPath: String) -> Bool {
        let std = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL.path
        let homeStd = PathConstants.homeDirectory.standardizedFileURL.path
        let effHomeStd = PathConstants.effectiveHomeDirectory.standardizedFileURL.path
        let geminiStd = PathConstants.geminiDirectory.standardizedFileURL.path
        let claudeStd = PathConstants.claudeDirectory.standardizedFileURL.path

        let exactRoots: Set<String> = [
            "/",
            "/Users",
            "/tmp",
            "/private/tmp",
            "/var",
            "/private/var",
            homeStd,
            effHomeStd,
            geminiStd,
            claudeStd
        ]
        if exactRoots.contains(std) {
            return true
        }

        let parentPath = URL(fileURLWithPath: std).deletingLastPathComponent().path
        let leafName = URL(fileURLWithPath: std).lastPathComponent
        if parentPath == "/Users" && !leafName.isEmpty {
            return true
        }

        let homeContainers: Set<String> = [
            "Desktop",
            "Documents",
            "Downloads",
            "Library",
            "Pictures",
            "Movies",
            "Music",
            "Public",
            "Applications",
            "AntigravityProfiles"
        ]
        if (parentPath == homeStd || parentPath == effHomeStd) && homeContainers.contains(leafName) {
            return true
        }
        let grandParentPath = URL(fileURLWithPath: parentPath).deletingLastPathComponent().path
        if grandParentPath == "/Users" && homeContainers.contains(leafName) {
            return true
        }
        return false
    }

    public func inspectStack(at projectPath: String) -> ProjectStackInspection {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        var info = ProjectStackInspection()
        guard !Self.isNonProjectContainerRoot(rootURL.path),
              fm.fileExists(atPath: rootURL.path) else {
            return info
        }
        let rootStd = rootURL.standardizedFileURL.path

        let topEntries = (try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        let topNames = Set(topEntries.map { $0.lastPathComponent })

        // 1. Apple / Swift / Xcode markers
        if topNames.contains("Package.swift") || topNames.contains("Project.swift") {
            info.hasSwiftPackage = true
            for manifestName in ["Package.swift", "Project.swift"] {
                let manifestURL = rootURL.appendingPathComponent(manifestName)
                if let text = try? String(contentsOf: manifestURL, encoding: .utf8) {
                    let lower = text.lowercased()
                    if lower.contains(".macos") || lower.contains("appkit") {
                        info.isMacOSTarget = true
                    }
                    if lower.contains(".ios") || lower.contains("uikit") {
                        info.isIOSTarget = true
                    }
                }
            }
        }

        var xcodeprojURLs: [URL] = []
        for entry in topEntries {
            let name = entry.lastPathComponent
            if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
                info.hasXcodeProject = true
                if name.hasSuffix(".xcodeproj") {
                    xcodeprojURLs.append(entry)
                }
            }
        }

        let lowerProjectName = rootURL.lastPathComponent.lowercased()
        if lowerProjectName.contains("ios") || lowerProjectName.contains("iphone") {
            info.isIOSTarget = true
        }
        if lowerProjectName.contains("mac") || lowerProjectName.contains("menubar") {
            info.isMacOSTarget = true
        }

        // Collect 1-level and 2-level subdirectories (bounded, excluding heavy/hidden/TCC container dirs)
        let ignoredDirs: Set<String> = ["node_modules", ".git", ".build", ".next", "dist", "build", ".agents", ".claude", "DerivedData"]
        var firstLevelDirs: [URL] = []
        var secondLevelDirs: [URL] = []
        for entry in topEntries where !ignoredDirs.contains(entry.lastPathComponent) && !entry.lastPathComponent.hasPrefix(".") {
            if Self.isNonProjectContainerRoot(entry.path) {
                continue
            }
            if PathConstants.isTCCProtectedPath(entry.path) && !PathConstants.isTCCProtectedPath(rootStd) {
                continue
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                firstLevelDirs.append(entry)
                if let subEntries = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
                    for sub in subEntries {
                        let subName = sub.lastPathComponent
                        if subName.hasSuffix(".xcodeproj") || subName.hasSuffix(".xcworkspace") {
                            info.hasXcodeProject = true
                            if subName.hasSuffix(".xcodeproj") {
                                xcodeprojURLs.append(sub)
                            }
                        } else if !ignoredDirs.contains(subName) && !subName.hasPrefix(".") && !Self.isNonProjectContainerRoot(sub.path) {
                            var subIsDir: ObjCBool = false
                            if fm.fileExists(atPath: sub.path, isDirectory: &subIsDir), subIsDir.boolValue {
                                secondLevelDirs.append(sub)
                            }
                        }
                    }
                }
            }
        }
        if !info.isIOSTarget && !info.isMacOSTarget {
            for xcodeproj in xcodeprojURLs {
                let pbxURL = xcodeproj.appendingPathComponent("project.pbxproj")
                if let pbxText = try? String(contentsOf: pbxURL, encoding: .utf8) {
                    if pbxText.contains("SDKROOT = iphoneos") {
                        info.isIOSTarget = true
                    } else if pbxText.contains("SDKROOT = macosx") {
                        info.isMacOSTarget = true
                    }
                }
            }
        }
        let candidateSubDirs = firstLevelDirs + secondLevelDirs

        if info.hasSwiftPackage || info.hasXcodeProject {
            if info.isMacOSTarget {
                info.stackLabels.append("Swift / macOS")
            } else if info.isIOSTarget {
                info.stackLabels.append("Xcode / iOS")
            } else {
                info.stackLabels.append("Swift / Apple")
            }
        }

        // 2. Collect package.json dependencies from root and bounded 1-2 level subdirectories
        var candidatePackageJsonURLs: [URL] = [rootURL.appendingPathComponent("package.json")]
        for subDir in candidateSubDirs {
            candidatePackageJsonURLs.append(subDir.appendingPathComponent("package.json"))
        }

        var allDeps: Set<String> = []
        for pkgFile in candidatePackageJsonURLs {
            if fm.fileExists(atPath: pkgFile.path) {
                info.hasPackageJson = true
                if let data = try? Data(contentsOf: pkgFile),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for section in ["dependencies", "devDependencies", "peerDependencies"] {
                        if let dict = json[section] as? [String: Any] {
                            for key in dict.keys {
                                allDeps.insert(key.lowercased())
                            }
                        }
                    }
                }
            }
        }
        info.npmDependencies = allDeps

        // 3. Evaluate dependency & file markers
        if topNames.contains("supabase")
            || firstLevelDirs.contains(where: { fm.fileExists(atPath: $0.appendingPathComponent("supabase").path) })
            || allDeps.contains(where: { $0.hasPrefix("@supabase/") || $0 == "supabase" }) {
            info.hasSupabaseMarker = true
            info.hasAuthOrDatabaseMarker = true
            info.stackLabels.append("Supabase")
        }

        if allDeps.contains(where: { $0.contains("posthog") }) {
            info.hasPostHogMarker = true
            info.stackLabels.append("PostHog")
        }

        if allDeps.contains(where: { $0.hasPrefix("@polar-sh/") || $0 == "polar" }) {
            info.hasPolarMarker = true
            info.hasAuthOrDatabaseMarker = true
            info.stackLabels.append("Polar.sh")
        }

        if topNames.contains("components.json")
            || firstLevelDirs.contains(where: { fm.fileExists(atPath: $0.appendingPathComponent("components.json").path) })
            || allDeps.contains(where: { $0.hasPrefix("@radix-ui/") || $0.contains("shadcn") }) {
            info.hasShadcnMarker = true
        }

        let webPackages: Set<String> = ["next", "react", "react-dom", "vue", "svelte", "@sveltejs/kit", "astro", "tailwindcss", "vite", "nuxt"]
        if !allDeps.intersection(webPackages).isEmpty
            || topNames.contains("next.config.js")
            || topNames.contains("next.config.mjs")
            || topNames.contains("next.config.ts")
            || topNames.contains("vite.config.ts")
            || topNames.contains("vite.config.js")
            || topNames.contains("tailwind.config.js")
            || topNames.contains("tailwind.config.ts")
            || topNames.contains("index.html") {
            info.hasWebFrontendMarker = true
            if allDeps.contains("next") {
                info.stackLabels.append("Next.js")
            } else if allDeps.contains("react") {
                info.stackLabels.append("React")
            } else {
                info.stackLabels.append("Web")
            }
        }

        if allDeps.contains(where: { $0 == "remotion" || $0.hasPrefix("@remotion/") })
            || topNames.contains(where: { $0.hasPrefix("remotion.config.") }) {
            info.hasRemotionMarker = true
            info.stackLabels.append("Remotion Video")
        }

        if topNames.contains("vercel.json")
            || topNames.contains(".vercel")
            || allDeps.contains(where: { $0.hasPrefix("@vercel/") || $0 == "vercel" }) {
            info.hasVercelMarker = true
        }

        if topNames.contains("netlify.toml")
            || topNames.contains(".netlify")
            || allDeps.contains(where: { $0.contains("netlify") }) {
            info.hasNetlifyMarker = true
        }

        if allDeps.contains(where: { $0 == "telegraf" || $0 == "grammy" || $0.contains("telegram") })
            || topNames.contains(where: { $0.lowercased().contains("telegram") })
            || fm.fileExists(atPath: rootURL.appendingPathComponent("Scripts/telegram_hook.sh").path) {
            info.hasTelegramMarker = true
            info.stackLabels.append("Telegram Bot")
        }

        if allDeps.contains(where: { $0.contains("brevo") || $0 == "sib-api-v3-sdk" }) {
            info.hasBrevoMarker = true
        }

        if allDeps.contains(where: { $0.hasPrefix("@aws-sdk/") || $0 == "aws-sdk" }) {
            info.hasAWSMarker = true
        }

        if topNames.contains("Dockerfile")
            || topNames.contains("docker-compose.yml")
            || topNames.contains("docker-compose.yaml")
            || topNames.contains("deploy.sh")
            || fm.fileExists(atPath: rootURL.appendingPathComponent("scripts/deploy.sh").path) {
            info.hasDockerOrVPSMarker = true
        }

        if topNames.contains("app.yaml") || topNames.contains("cloudbuild.yaml") || allDeps.contains(where: { $0.hasPrefix("@google-cloud/") }) {
            info.hasGCloudMarker = true
        }

        if topNames.contains(".do") {
            info.hasDigitalOceanMarker = true
        }

        if allDeps.contains(where: {
            $0.contains("prisma") || $0.contains("drizzle") || $0.contains("next-auth")
            || $0.contains("better-auth") || $0.contains("clerk") || $0.contains("stripe")
        }) {
            info.hasAuthOrDatabaseMarker = true
        }

        return info
    }

    public func recommend(
        for project: ProjectProfile,
        availableServers: [MCPServerDefinition],
        globalServerIds: Set<String>,
        availableSkills: [SkillDefinition],
        globalSkillIds: Set<String>,
        projectLocalSkillIds: Set<String> = [],
        availablePlugins: [PluginDefinition],
        globalPluginIds: Set<String>
    ) -> [ResourceRecommendation] {
        let stack = inspectStack(at: project.path)
        return buildRecommendations(
            stack: stack,
            project: project,
            availableServers: availableServers,
            globalServerIds: globalServerIds,
            availableSkills: availableSkills,
            globalSkillIds: globalSkillIds,
            projectLocalSkillIds: projectLocalSkillIds,
            availablePlugins: availablePlugins,
            globalPluginIds: globalPluginIds
        )
    }

    public func buildRecommendations(
        stack: ProjectStackInspection,
        project: ProjectProfile,
        availableServers: [MCPServerDefinition],
        globalServerIds: Set<String>,
        availableSkills: [SkillDefinition],
        globalSkillIds: Set<String>,
        projectLocalSkillIds: Set<String> = [],
        availablePlugins: [PluginDefinition],
        globalPluginIds: Set<String>
    ) -> [ResourceRecommendation] {
        let serverMap = Dictionary(uniqueKeysWithValues: availableServers.map { ($0.id, $0) })
        let skillMap = Dictionary(uniqueKeysWithValues: availableSkills.map { ($0.id, $0) })
        let pluginMap = Dictionary(uniqueKeysWithValues: availablePlugins.map { ($0.id, $0) })

        let activeServerIds = globalServerIds.union(project.enabledMCPServerIds)
        let activePluginIds = globalPluginIds.union(project.enabledPluginIds)
        var activeSkillIds = globalSkillIds.union(project.enabledSkillIds).union(projectLocalSkillIds)

        // Include skills and MCPs bundled inside already-enabled plugins so we don't recommend duplicates
        let fm = FileManager.default
        var bundledServerIds: Set<String> = []
        for pluginId in activePluginIds {
            if let plugin = pluginMap[pluginId] {
                let pluginURL = URL(fileURLWithPath: plugin.path)
                let skillsDir = pluginURL.appendingPathComponent("skills", isDirectory: true)
                if let subItems = try? fm.contentsOfDirectory(atPath: skillsDir.path) {
                    activeSkillIds.formUnion(subItems)
                }
                let mcpFile = pluginURL.appendingPathComponent("mcp_config.json")
                if let data = try? Data(contentsOf: mcpFile),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let mcpServers = json["mcpServers"] as? [String: Any] {
                    bundledServerIds.formUnion(mcpServers.keys)
                }
            }
        }
        let allActiveServerIds = activeServerIds.union(bundledServerIds)

        var recommendations: [ResourceRecommendation] = []
        var seenKeys: Set<String> = []

        func addMCP(_ id: String, reason: String, priority: RecommendationPriority = .high) {
            guard !allActiveServerIds.contains(id), let server = serverMap[id] else { return }
            let rec = ResourceRecommendation(id: server.id, name: server.name, kind: .mcp, reason: reason, priority: priority)
            if seenKeys.insert(rec.uniqueKey).inserted {
                recommendations.append(rec)
            }
        }

        func addSkill(_ id: String, reason: String, priority: RecommendationPriority = .medium) {
            guard !activeSkillIds.contains(id), let skill = skillMap[id] else { return }
            let rec = ResourceRecommendation(id: skill.id, name: skill.name, kind: .skill, reason: reason, priority: priority)
            if seenKeys.insert(rec.uniqueKey).inserted {
                recommendations.append(rec)
            }
        }

        func addPlugin(_ id: String, reason: String, priority: RecommendationPriority = .high) {
            guard !activePluginIds.contains(id), let plugin = pluginMap[id] else { return }
            let rec = ResourceRecommendation(id: plugin.id, name: plugin.name, kind: .plugin, reason: reason, priority: priority)
            if seenKeys.insert(rec.uniqueKey).inserted {
                recommendations.append(rec)
            }
        }

        // 1. Apple / Swift / Xcode recommendations
        if stack.hasSwiftPackage || stack.hasXcodeProject {
            let stackDesc = stack.isMacOSTarget
                ? "Detected Swift / macOS project"
                : (stack.isIOSTarget ? "Detected Xcode / iOS project" : "Detected Swift / Apple project")

            if stack.isMacOSTarget || !stack.isIOSTarget {
                addPlugin("build-macos-apps", reason: "\(stackDesc) (SwiftUI/AppKit engineering plugin)", priority: .high)
                addSkill("macos-ui-design-pro", reason: "\(stackDesc) — Apple HIG & SwiftUI design system", priority: .high)
                addSkill("macos-spm-app-packaging", reason: "\(stackDesc) — SwiftPM .app packaging & code signing", priority: .medium)
                addSkill("macos-menubar-tuist-app", reason: "\(stackDesc) — Menubar / Tuist architecture", priority: .low)
            }

            // Recommend any other Swift & Apple skills in the Vault that match target
            for skill in availableSkills where skill.category == "Swift & Apple" {
                let lowerId = skill.id.lowercased()
                if stack.isIOSTarget && !stack.isMacOSTarget && lowerId.contains("macos") {
                    continue
                }
                addSkill(skill.id, reason: "\(stackDesc) (Apple/Swift skill available in Vault)", priority: .medium)
            }
        }

        // 2. Supabase
        if stack.hasSupabaseMarker {
            addMCP("supabase", reason: "Detected Supabase in project", priority: .high)
        }

        // 3. PostHog
        if stack.hasPostHogMarker {
            addMCP("posthog", reason: "Detected PostHog analytics in package.json", priority: .high)
        }

        // 4. Polar
        if stack.hasPolarMarker {
            addMCP("polar", reason: "Detected Polar.sh SDK in package.json", priority: .high)
            addMCP("polar-sandbox", reason: "Detected Polar.sh SDK (sandbox environment)", priority: .medium)
        }

        // 5. Shadcn & Web Frontend
        if stack.hasShadcnMarker {
            addMCP("shadcn", reason: "Detected shadcn/ui in project", priority: .high)
        }

        if stack.hasWebFrontendMarker {
            addPlugin("modern-web-guidance-plugin", reason: "Detected Web/Frontend stack", priority: .high)
            addPlugin("chrome-devtools-plugin", reason: "Recommended for inspecting and debugging Web UI", priority: .medium)
            addSkill("ui-architect", reason: "Recommended for Web UI architecture and layout", priority: .medium)
            addSkill("vercel-web-design-guidelines", reason: "Recommended for Web UI/UX standards", priority: .medium)
            addSkill("react-component-performance", reason: "Recommended for React component optimization", priority: .medium)
            addSkill("no-ai-slop", reason: "Recommended for clean production UI design", priority: .low)
            addSkill("ui-unslop-by-damir-sokolovsky", reason: "Recommended for UI polish and micro-details", priority: .low)
            addSkill("benji-landing-animations", reason: "Recommended for Web animations and micro-interactions", priority: .low)
        }

        // 6. Remotion
        if stack.hasRemotionMarker {
            for skill in availableSkills where skill.category == "Video & Remotion" || skill.id.lowercased().contains("remotion") {
                addSkill(skill.id, reason: "Detected Remotion video project", priority: .high)
            }
        }

        // 7. Vercel / Netlify
        if stack.hasVercelMarker {
            addMCP("vercel", reason: "Detected Vercel configuration in project", priority: .high)
        }
        if stack.hasNetlifyMarker {
            addMCP("netlify", reason: "Detected Netlify configuration in project", priority: .high)
        }

        // 8. Telegram
        if stack.hasTelegramMarker {
            addMCP("telegram", reason: "Detected Telegram integration in project", priority: .high)
            addSkill("telegram-bot-builder", reason: "Detected Telegram bot script or dependency", priority: .high)
        }

        // 9. Brevo / AWS
        if stack.hasBrevoMarker {
            addMCP("brevo", reason: "Detected Brevo email SDK in package.json", priority: .high)
        }
        if stack.hasAWSMarker {
            addSkill("aws-ops", reason: "Detected AWS SDK in project", priority: .high)
        }

        // 10. DevOps / Docker / Cloud
        if stack.hasDockerOrVPSMarker {
            addSkill("hetzner-vps-ops", reason: "Detected Dockerfile / deployment configuration", priority: .medium)
        }
        if stack.hasGCloudMarker {
            addMCP("gcloud", reason: "Detected Google Cloud configuration", priority: .high)
        }
        if stack.hasDigitalOceanMarker {
            addMCP("digitalocean", reason: "Detected DigitalOcean configuration", priority: .high)
        }

        // 11. Security review for auth/payment/db projects
        if stack.hasAuthOrDatabaseMarker {
            addSkill("security-review", reason: "Recommended for projects with databases, auth, or billing", priority: .low)
        }

        return recommendations.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.kind.rawValue != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.id < rhs.id
        }
    }
}
