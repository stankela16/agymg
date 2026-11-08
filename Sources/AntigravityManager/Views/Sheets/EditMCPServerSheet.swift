import SwiftUI

public struct EditMCPServerSheet: View {
    @Bindable var state: AppState
    public let server: MCPServerDefinition?
    public var addToGlobal: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var serverId: String = ""
    @State private var displayName: String = ""
    @State private var selectedCategory: String = "Tools"
    @State private var transportMode: TransportMode = .stdio
    @State private var command: String = "npx"
    @State private var argsText: String = ""
    @State private var envPairs: [EnvPair] = []
    @State private var serverUrl: String = ""
    @State private var headerPairs: [EnvPair] = []
    @State private var activateGlobally: Bool = false
    @State private var isSaving: Bool = false

    public enum TransportMode: String, CaseIterable, Identifiable {
        case stdio = "Command (Stdio)"
        case remote = "Remote (SSE / HTTP)"
        public var id: String { rawValue }
    }

    public struct EnvPair: Identifiable {
        public let id = UUID()
        public var key: String
        public var value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    private let categories = [
        "Tools", "Database", "Git", "Cloud", "Analytics", "Communication", "Payments", "Design"
    ]

    public init(state: AppState, server: MCPServerDefinition? = nil, addToGlobal: Bool = false) {
        self.state = state
        self.server = server
        self.addToGlobal = addToGlobal
    }

    private var isEditing: Bool { server != nil }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    // ID & Name
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server ID")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.ink)
                            TextField("e.g., supabase", text: $serverId)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isEditing)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Display Name")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.ink)
                            TextField("e.g., Supabase DB", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Category & Transport
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.ink)
                            Picker("", selection: $selectedCategory) {
                                ForEach(categories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transport Type")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.ink)
                            Picker("", selection: $transportMode) {
                                ForEach(TransportMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }

                    Divider().padding(.vertical, 2)

                    if transportMode == .stdio {
                        stdioConfigSection
                    } else {
                        remoteConfigSection
                    }

                    Divider().padding(.vertical, 2)

                    Toggle("Enable immediately in Global Core (all projects)", isOn: $activateGlobally)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.ink)
                }
                .padding(DesignTokens.Spacing.lg)
            }

            Divider()
            footerBar
        }
        .frame(width: 580, height: 600)
        .background(DesignTokens.background)
        .onAppear { loadInitialData() }
    }

    private var stdioConfigSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Executable Command")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                TextField("e.g., npx, uvx, or /opt/homebrew/bin/node", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Command Arguments")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                    Spacer()
                    Text("One argument per line")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
                TextEditor(text: $argsText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                    .padding(4)
                    .background(DesignTokens.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Environment Variables
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Environment Variables (env)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                    Spacer()
                    Button("+ Add Variable") {
                        envPairs.append(EnvPair(key: "", value: ""))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if envPairs.isEmpty {
                    Text("No environment variables defined.")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.inkTertiary)
                } else {
                    ForEach($envPairs) { $pair in
                        HStack(spacing: 6) {
                            TextField("KEY", text: $pair.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 180)
                            Text("=")
                                .foregroundStyle(DesignTokens.inkTertiary)
                            TextField("VALUE", text: $pair.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10, design: .monospaced))
                            Button {
                                envPairs.removeAll { $0.id == pair.id }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color(hex: 0xF5222D))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var remoteConfigSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.ink)
                TextField("https://api.example.com/mcp/sse", text: $serverUrl)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }

            // Headers
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("HTTP Headers")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)
                    Spacer()
                    Button("+ Add Header") {
                        headerPairs.append(EnvPair(key: "", value: ""))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach($headerPairs) { $pair in
                    HStack(spacing: 6) {
                        TextField("Header-Name", text: $pair.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 160)
                        Text(":")
                            .foregroundStyle(DesignTokens.inkTertiary)
                        TextField("Value", text: $pair.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10, design: .monospaced))
                        Button {
                            headerPairs.removeAll { $0.id == pair.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color(hex: 0xF5222D))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "server.rack")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.secondary)
            Text(isEditing ? "Edit MCP Server (\(server?.id ?? ""))" : "New MCP Server")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var footerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                saveAction()
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(isEditing ? "Save Changes" : "Add Server")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
            .disabled(serverId.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func loadInitialData() {
        if let s = server {
            serverId = s.id
            displayName = s.name
            selectedCategory = s.category
            activateGlobally = state.globalServerIds.contains(s.id)

            if let url = s.serverUrl {
                transportMode = .remote
                serverUrl = url
                if let headersObj = s.config["headers"]?.objectValue {
                    headerPairs = headersObj.map { EnvPair(key: $0.key, value: $0.value.stringValue ?? "") }
                }
            } else {
                transportMode = .stdio
                command = s.command ?? "npx"
                if let args = s.config["args"]?.arrayValue {
                    argsText = args.compactMap { $0.stringValue }.joined(separator: "\n")
                }
                if let envObj = s.config["env"]?.objectValue {
                    envPairs = envObj.map { EnvPair(key: $0.key, value: $0.value.stringValue ?? "") }
                }
            }
        } else {
            activateGlobally = addToGlobal
        }
    }

    private func saveAction() {
        let cleanId = serverId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanId.isEmpty else { return }

        isSaving = true

        var newConfig: [String: JSONValue] = server?.config ?? [:]

        if transportMode == .stdio {
            newConfig["command"] = .string(command.trimmingCharacters(in: .whitespaces))
            newConfig.removeValue(forKey: "serverUrl")
            newConfig.removeValue(forKey: "headers")

            let args = argsText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !args.isEmpty {
                newConfig["args"] = .array(args.map { .string($0) })
            } else {
                newConfig.removeValue(forKey: "args")
            }

            var envDict: [String: JSONValue] = [:]
            for pair in envPairs where !pair.key.trimmingCharacters(in: .whitespaces).isEmpty {
                envDict[pair.key.trimmingCharacters(in: .whitespaces)] = .string(pair.value)
            }
            if !envDict.isEmpty {
                newConfig["env"] = .object(envDict)
            } else {
                newConfig.removeValue(forKey: "env")
            }
        } else {
            newConfig["serverUrl"] = .string(serverUrl.trimmingCharacters(in: .whitespaces))
            newConfig.removeValue(forKey: "command")
            newConfig.removeValue(forKey: "args")
            newConfig.removeValue(forKey: "env")

            var hDict: [String: JSONValue] = [:]
            for pair in headerPairs where !pair.key.trimmingCharacters(in: .whitespaces).isEmpty {
                hDict[pair.key.trimmingCharacters(in: .whitespaces)] = .string(pair.value)
            }
            if !hDict.isEmpty {
                newConfig["headers"] = .object(hDict)
            } else {
                newConfig.removeValue(forKey: "headers")
            }
        }

        let name = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? cleanId : displayName
        let updatedDef = MCPServerDefinition(id: cleanId, name: name, category: selectedCategory, config: newConfig)

        Task {
            await state.saveServer(updatedDef, enableGlobally: activateGlobally)
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}
