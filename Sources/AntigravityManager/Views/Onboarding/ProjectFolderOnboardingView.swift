import SwiftUI

public struct ProjectFolderOnboardingView: View {
    @Bindable var state: AppState
    @State private var didJustAuthorize: Bool = false

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DesignTokens.Spacing.sm)

            if didJustAuthorize {
                OnboardingSuccessBadge(
                    projectCount: state.projects.count,
                    projectNames: state.projects.map(\.name)
                ) {
                    withAnimation(DesignTokens.smoothSpring) {
                        state.isProjectsFolderAuthorized = true
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .opacity
                ))
            } else {
                welcomeContent
                    .transition(.opacity)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .background(DesignTokens.background)
    }

    private var welcomeContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            OnboardingHeaderView()
            OnboardingFeatureList()
            actionButtons
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                Task {
                    let success = await state.authorizeProjectsFolder(updateAuthorizationState: false)
                    if success {
                        withAnimation(DesignTokens.smoothSpring) {
                            didJustAuthorize = true
                        }
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "folder.badge.plus")
                    Text("Connect Projects Folder…")
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 220)
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.secondary)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .help("Choose your root projects folder to authorize workspace discovery (Return)")

            Button("Skip for now (Global Vault Only)") {
                ProjectFolderAccessManager.shared.isAuthorized = true
                withAnimation(DesignTokens.smoothSpring) {
                    state.isProjectsFolderAuthorized = true
                }
                Task {
                    await state.refreshProjects()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.inkTertiary)
            .padding(.top, DesignTokens.Spacing.xxs)
        }
    }
}
