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
    public var hasCloudflareMarker: Bool = false
    public var hasGeminiAPIMarker: Bool = false
    public var hasESP32Marker: Bool = false
    public var hasFigmaMarker: Bool = false
    public var hasPythonMarker: Bool = false
    public var pythonDependencies: Set<String> = []
    public var hasGoMarker: Bool = false
    public var hasRustMarker: Bool = false
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

        func appendLabel(_ label: String) {
            if !info.stackLabels.contains(label) {
                info.stackLabels.append(label)
            }
        }

        if info.hasSwiftPackage || info.hasXcodeProject {
            if info.isMacOSTarget {
                appendLabel("Swift / macOS")
            } else if info.isIOSTarget {
                appendLabel("Xcode / iOS")
            } else {
                appendLabel("Swift / Apple")
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

        // 2b. Collect Python markers & dependencies (requirements.txt, pyproject.toml, Pipfile, uv.lock)
        let candidateRoots = [rootURL] + firstLevelDirs
        var pyDeps: Set<String> = []
        let pythonFileMarkers = ["pyproject.toml", "requirements.txt", "Pipfile", "uv.lock"]
        for dirURL in candidateRoots {
            for marker in pythonFileMarkers {
                let markerURL = dirURL.appendingPathComponent(marker)
                if fm.fileExists(atPath: markerURL.path) {
                    info.hasPythonMarker = true
                    if marker == "requirements.txt", let text = try? String(contentsOf: markerURL, encoding: .utf8) {
                        Self.extractRequirementsPackages(from: text, into: &pyDeps)
                    } else if marker == "pyproject.toml", let text = try? String(contentsOf: markerURL, encoding: .utf8) {
                        Self.extractPyprojectPackages(from: text, into: &pyDeps)
                    }
                }
            }
        }
        info.pythonDependencies = pyDeps
        if info.hasPythonMarker {
            appendLabel("Python")
        }

        // 2c. Go & Rust markers
        if candidateRoots.contains(where: { fm.fileExists(atPath: $0.appendingPathComponent("go.mod").path) }) {
            info.hasGoMarker = true
            appendLabel("Go")
        }
        if candidateRoots.contains(where: { fm.fileExists(atPath: $0.appendingPathComponent("Cargo.toml").path) }) {
            info.hasRustMarker = true
            appendLabel("Rust")
        }

        // 3. Evaluate dependency & file markers
        if topNames.contains("supabase")
            || firstLevelDirs.contains(where: { fm.fileExists(atPath: $0.appendingPathComponent("supabase").path) })
            || allDeps.contains(where: { $0.hasPrefix("@supabase/") || $0 == "supabase" })
            || pyDeps.contains("supabase") {
            info.hasSupabaseMarker = true
            info.hasAuthOrDatabaseMarker = true
            appendLabel("Supabase")
        }

        if allDeps.contains(where: { $0.contains("posthog") }) || pyDeps.contains("posthog") {
            info.hasPostHogMarker = true
            appendLabel("PostHog")
        }

        if allDeps.contains(where: { $0.hasPrefix("@polar-sh/") || $0 == "polar" }) {
            info.hasPolarMarker = true
            info.hasAuthOrDatabaseMarker = true
            appendLabel("Polar.sh")
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
                appendLabel("Next.js")
            } else if allDeps.contains("react") {
                appendLabel("React")
            } else {
                appendLabel("Web")
            }
        }

        if allDeps.contains(where: { $0 == "remotion" || $0.hasPrefix("@remotion/") })
            || topNames.contains(where: { $0.hasPrefix("remotion.config.") }) {
            info.hasRemotionMarker = true
            appendLabel("Remotion Video")
        }

        let cloudflareFiles = ["wrangler.toml", "wrangler.json", "wrangler.jsonc"]
        if candidateRoots.contains(where: { dir in cloudflareFiles.contains(where: { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }) })
            || allDeps.contains(where: { $0.hasPrefix("@cloudflare/") || $0 == "wrangler" }) {
            info.hasCloudflareMarker = true
            appendLabel("Cloudflare")
        }

        if allDeps.contains(where: { $0 == "@google/genai" || $0 == "@google/generative-ai" })
            || pyDeps.contains("google-genai")
            || pyDeps.contains("google-generativeai") {
            info.hasGeminiAPIMarker = true
            appendLabel("Gemini API")
        }

        let hasInoRoot = topNames.contains(where: { $0.lowercased().hasSuffix(".ino") })
        if hasInoRoot
            || candidateRoots.contains(where: {
                fm.fileExists(atPath: $0.appendingPathComponent("platformio.ini").path)
                || fm.fileExists(atPath: $0.appendingPathComponent("sdkconfig").path)
            }) {
            info.hasESP32Marker = true
            appendLabel("ESP32 / Embedded")
        }

        if topNames.contains("figma.config.json")
            || topNames.contains(".figmarc")
            || allDeps.contains(where: { $0.hasPrefix("@figma/") }) {
            info.hasFigmaMarker = true
            appendLabel("Figma")
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
            || pyDeps.contains(where: { $0 == "python-telegram-bot" || $0 == "aiogram" || $0 == "pytelegrambotapi" || $0 == "telethon" })
            || topNames.contains(where: { $0.lowercased().contains("telegram") })
            || fm.fileExists(atPath: rootURL.appendingPathComponent("Scripts/telegram_hook.sh").path) {
            info.hasTelegramMarker = true
            appendLabel("Telegram Bot")
        }

        if allDeps.contains(where: { $0.contains("brevo") || $0 == "sib-api-v3-sdk" }) {
            info.hasBrevoMarker = true
        }

        if allDeps.contains(where: { $0.hasPrefix("@aws-sdk/") || $0 == "aws-sdk" })
            || pyDeps.contains("boto3")
            || pyDeps.contains("botocore") {
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
        }) || pyDeps.contains(where: {
            $0 == "fastapi" || $0 == "django" || $0 == "flask" || $0 == "prisma" || $0 == "sqlalchemy" || $0 == "stripe"
        }) {
            info.hasAuthOrDatabaseMarker = true
        }

        return info
    }

    private static func extractRequirementsPackages(from text: String, into set: inout Set<String>) {
        let separators = CharacterSet(charactersIn: "=<>!~;[ \t\"")
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("-") { continue }
            let token = trimmed.components(separatedBy: separators).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if !token.isEmpty {
                set.insert(token.replacingOccurrences(of: "_", with: "-"))
            }
        }
    }

    private static func extractPyprojectPackages(from text: String, into set: inout Set<String>) {
        let lower = text.lowercased()
        let knownPackages = [
            "supabase", "google-genai", "google-generativeai", "posthog",
            "python-telegram-bot", "aiogram", "pytelegrambotapi", "telethon",
            "boto3", "botocore", "fastapi", "django", "flask", "prisma", "sqlalchemy", "stripe"
        ]
        let normalized = lower.replacingOccurrences(of: "_", with: "-")
        for pkg in knownPackages {
            if normalized.contains("\"\(pkg)") || normalized.contains("'\(pkg)") || normalized.contains(" \(pkg)") || normalized.contains("\n\(pkg)") {
                set.insert(pkg)
            }
        }
    }

    public func recommend(
        for project: ProjectProfile,
        availableServers: [MCPServerDefinition],
        globalServerIds: Set<String>,
        availableSkills: [SkillDefinition],
        globalSkillIds: Set<String>,
        projectLocalSkillIds: Set<String> = [],
        availablePlugins: [PluginDefinition],
        globalPluginIds: Set<String>,
        includeDismissed: Bool = false
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
            globalPluginIds: globalPluginIds,
            includeDismissed: includeDismissed
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
        globalPluginIds: Set<String>,
        includeDismissed: Bool = false
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

        let dismissedKeys = includeDismissed ? [] : project.dismissedRecommendationKeys

        func addMCP(_ id: String, reason: String, priority: RecommendationPriority = .high) {
            guard !allActiveServerIds.contains(id), let server = serverMap[id] else { return }
            let rec = ResourceRecommendation(id: server.id, name: server.name, kind: .mcp, reason: reason, priority: priority)
            guard !dismissedKeys.contains(rec.uniqueKey) else { return }
            if seenKeys.insert(rec.uniqueKey).inserted {
                recommendations.append(rec)
            }
        }

        func addSkill(_ id: String, reason: String, priority: RecommendationPriority = .medium) {
            guard !activeSkillIds.contains(id), let skill = skillMap[id] else { return }
            let rec = ResourceRecommendation(id: skill.id, name: skill.name, kind: .skill, reason: reason, priority: priority)
            guard !dismissedKeys.contains(rec.uniqueKey) else { return }
            if seenKeys.insert(rec.uniqueKey).inserted {
                recommendations.append(rec)
            }
        }

        func addPlugin(_ id: String, reason: String, priority: RecommendationPriority = .high) {
            guard !activePluginIds.contains(id), let plugin = pluginMap[id] else { return }
            let rec = ResourceRecommendation(id: plugin.id, name: plugin.name, kind: .plugin, reason: reason, priority: priority)
            guard !dismissedKeys.contains(rec.uniqueKey) else { return }
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

            if stack.isIOSTarget {
                addSkill("apple-onboarding-cro", reason: "Detected iOS project — App Store & onboarding optimization", priority: .medium)
            }
        }

        // 2. Supabase
        if stack.hasSupabaseMarker {
            addMCP("supabase", reason: "Detected Supabase in project", priority: .high)
        }

        // 3. PostHog
        if stack.hasPostHogMarker {
            addMCP("posthog", reason: "Detected PostHog analytics in project", priority: .high)
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

        // 8. Cloudflare / Gemini API / ESP32 / Figma
        if stack.hasCloudflareMarker {
            addPlugin("cloudflare", reason: "Detected Cloudflare Workers / Wrangler configuration", priority: .high)
            if serverMap["cloudflare"] != nil {
                addMCP("cloudflare", reason: "Detected Cloudflare project", priority: .high)
            } else {
                addMCP("cloudflare_cloudflare", reason: "Detected Cloudflare project", priority: .high)
            }
        }
        if stack.hasGeminiAPIMarker {
            addPlugin("gemini-api", reason: "Detected Google Gemini SDK in project dependencies", priority: .high)
        }
        if stack.hasESP32Marker {
            addSkill("esp32-desk-gadget", reason: "Detected ESP32 / PlatformIO embedded firmware project", priority: .high)
        }
        if stack.hasFigmaMarker {
            addPlugin("figma", reason: "Detected Figma integration in project", priority: .medium)
            if serverMap["figma"] != nil {
                addMCP("figma", reason: "Detected Figma configuration in project", priority: .medium)
            } else {
                addMCP("figma_figma", reason: "Detected Figma configuration in project", priority: .medium)
            }
        }

        // 9. Telegram
        if stack.hasTelegramMarker {
            addMCP("telegram", reason: "Detected Telegram integration in project", priority: .high)
            addSkill("telegram-bot-builder", reason: "Detected Telegram bot script or dependency", priority: .high)
        }

        // 10. Brevo / AWS
        if stack.hasBrevoMarker {
            addMCP("brevo", reason: "Detected Brevo email SDK in package.json", priority: .high)
        }
        if stack.hasAWSMarker {
            addSkill("aws-ops", reason: "Detected AWS SDK in project", priority: .high)
        }

        // 11. DevOps / Docker / Cloud
        if stack.hasDockerOrVPSMarker {
            addSkill("hetzner-vps-ops", reason: "Detected Dockerfile / deployment configuration", priority: .medium)
        }
        if stack.hasGCloudMarker {
            addMCP("gcloud", reason: "Detected Google Cloud configuration", priority: .high)
        }
        if stack.hasDigitalOceanMarker {
            addMCP("digitalocean", reason: "Detected DigitalOcean configuration", priority: .high)
        }

        // 12. Security review for auth/payment/db projects
        if stack.hasAuthOrDatabaseMarker {
            addSkill("security-review", reason: "Recommended for projects with databases, auth, or billing", priority: .low)
        }

        // 13. Dynamic YAML frontmatter matching for new Vault skills (capped at 4 low-priority matches)
        let stackTokens = Self.detectedTechnologyTokens(from: stack)
        if !stackTokens.isEmpty {
            let metaSkillIds: Set<String> = [
                "ask", "vault", "handoff", "grill-plan", "boost-mode",
                "skill-creator", "consult-claude", "consult-antigravity",
                "logo-design", "automation", "plugin", "run-workflow"
            ]
            var dynamicCount = 0
            let sortedVaultSkills = availableSkills.sorted { $0.id < $1.id }
            for skill in sortedVaultSkills {
                guard dynamicCount < 4 else { break }
                let lowerId = skill.id.lowercased()
                if metaSkillIds.contains(lowerId) { continue }
                if stack.isIOSTarget && !stack.isMacOSTarget && (lowerId.contains("macos") || lowerId.contains("appkit")) {
                    continue
                }
                let dummyKey = "skill:\(skill.id)"
                if activeSkillIds.contains(skill.id) || seenKeys.contains(dummyKey) || dismissedKeys.contains(dummyKey) {
                    continue
                }
                let skillWords = Self.tokenize("\(skill.id) \(skill.name) \(skill.description)")
                if let matched = stackTokens.sorted().first(where: { skillWords.contains($0) }) {
                    addSkill(skill.id, reason: "Matches detected \(matched) in repository (Vault skill)", priority: .low)
                    dynamicCount += 1
                }
            }
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

    private static func detectedTechnologyTokens(from stack: ProjectStackInspection) -> Set<String> {
        var tokens: Set<String> = []
        if stack.hasCloudflareMarker { tokens.formUnion(["cloudflare", "wrangler"]) }
        if stack.hasGeminiAPIMarker { tokens.insert("gemini") }
        if stack.hasESP32Marker { tokens.formUnion(["esp32", "platformio"]) }
        if stack.hasFigmaMarker { tokens.insert("figma") }
        if stack.hasPythonMarker {
            tokens.insert("python")
            if stack.pythonDependencies.contains("fastapi") { tokens.insert("fastapi") }
            if stack.pythonDependencies.contains("django") { tokens.insert("django") }
        }
        if stack.hasGoMarker { tokens.insert("golang") }
        if stack.hasRustMarker { tokens.insert("rust") }
        if stack.hasSwiftPackage || stack.hasXcodeProject {
            tokens.formUnion(["swift", "swiftui"])
            if stack.isMacOSTarget { tokens.insert("macos") }
            if stack.isIOSTarget { tokens.insert("ios") }
        }
        if stack.hasWebFrontendMarker {
            if stack.npmDependencies.contains("next") { tokens.insert("nextjs") }
            if stack.npmDependencies.contains("react") { tokens.insert("react") }
            if stack.npmDependencies.contains("tailwindcss") { tokens.insert("tailwind") }
            if stack.npmDependencies.contains("astro") { tokens.insert("astro") }
            if stack.npmDependencies.contains("svelte") || stack.npmDependencies.contains("@sveltejs/kit") { tokens.insert("svelte") }
            if stack.npmDependencies.contains("vue") { tokens.insert("vue") }
            if stack.npmDependencies.contains("nuxt") { tokens.insert("nuxt") }
        }
        if stack.hasSupabaseMarker { tokens.insert("supabase") }
        if stack.hasRemotionMarker { tokens.insert("remotion") }
        if stack.hasTelegramMarker { tokens.insert("telegram") }
        if stack.hasDockerOrVPSMarker { tokens.insert("docker") }
        if stack.hasVercelMarker { tokens.insert("vercel") }
        if stack.hasNetlifyMarker { tokens.insert("netlify") }
        if stack.hasPostHogMarker { tokens.insert("posthog") }
        if stack.hasPolarMarker { tokens.insert("polar") }
        if stack.hasShadcnMarker { tokens.insert("shadcn") }
        if stack.npmDependencies.contains(where: { $0.contains("prisma") }) || stack.pythonDependencies.contains("prisma") {
            tokens.insert("prisma")
        }
        if stack.npmDependencies.contains(where: { $0.contains("drizzle") }) {
            tokens.insert("drizzle")
        }
        if stack.npmDependencies.contains(where: { $0.contains("stripe") }) || stack.pythonDependencies.contains("stripe") {
            tokens.insert("stripe")
        }
        return tokens
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        let parts = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count >= 2 })
    }
}
