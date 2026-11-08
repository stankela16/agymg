import SwiftUI

/// Comprehensive Settings scene compliant with Apple HIG and App Store Review Guideline 2.4.5.
public struct SettingsView: View {
    @Bindable var state: AppState
    @State private var selectedTab: SettingsTab = .general

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case vault = "Vault & Sync"
        case compliance = "HIG & Compliance"

        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .general: return "gearshape"
            case .vault: return "shield.lefthalf.filled"
            case .compliance: return "checkmark.seal"
            }
        }
    }

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            SettingsGeneralTab(state: state)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            SettingsVaultTab(state: state)
                .tabItem {
                    Label("Vault & Sync", systemImage: "shield.lefthalf.filled")
                }
                .tag(SettingsTab.vault)

            SettingsComplianceTab()
                .tabItem {
                    Label("About & HIG", systemImage: "checkmark.seal")
                }
                .tag(SettingsTab.compliance)
        }
        .frame(width: 540, height: 420)
        .padding(DesignTokens.Spacing.md)
    }
}
