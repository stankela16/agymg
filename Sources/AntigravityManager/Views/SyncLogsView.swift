import SwiftUI
import AppKit

public struct SyncLogsView: View {
    @Bindable var state: AppState
    @State private var searchText: String = ""
    @State private var selectedStatus: SyncLogStatus? = nil
    @State private var selectedCategory: SyncLogCategory? = nil
    @State private var expandedEntryIds: Set<UUID> = []
    @State private var showClearConfirmation: Bool = false

    public init(state: AppState) {
        self.state = state
    }

    private var filteredLogs: [SyncLogEntry] {
        state.syncHistory.filter { entry in
            let matchesStatus = selectedStatus == nil || entry.status == selectedStatus
            let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                entry.targetName.localizedCaseInsensitiveContains(searchText) ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                (entry.details?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesStatus && matchesCategory && matchesSearch
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                headerSection
                kpiMetricsStrip
                filterAndSearchBar

                if state.syncHistory.isEmpty {
                    emptyHistoryView
                        .padding(.vertical, DesignTokens.Spacing.xl)
                } else if filteredLogs.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.xl)
                } else {
                    logsList
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.background)
        .confirmationDialog(
            "Are you sure you want to clear all logs?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Logs", role: .destructive) {
                state.clearSyncHistory()
                expandedEntryIds.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action clears the synchronization history for the current session.")
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(DesignTokens.primary)
                    Text("Sync Engine Logs")
                        .font(.title2.bold())
                        .foregroundStyle(DesignTokens.ink)
                }
                Text("Real-time telemetry of configuration files, symlinks, and manifest synchronization.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.inkSecondary)
            }

            Spacer()

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    copyAllLogs()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.syncHistory.isEmpty)
                .help("Copy all logs to clipboard")

                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.syncHistory.isEmpty)
                .help("Clear log history (⌘K)")

                Button {
                    state.syncAll()
                } label: {
                    HStack(spacing: 4) {
                        if state.isSyncing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(state.isSyncing ? "Syncing..." : "Sync All Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignTokens.primaryContainer)
                .disabled(state.isSyncing)
                .help("Run full synchronization to disk")
            }
        }
    }

    // MARK: - KPI Metrics Strip
    private var kpiMetricsStrip: some View {
        let totalCount = state.syncHistory.count
        let successCount = state.syncHistory.filter { $0.status == .success }.count
        let warningCount = state.syncHistory.filter { $0.status == .warning }.count
        let failureCount = state.syncHistory.filter { $0.status == .failure }.count
        let lastSyncText = state.lastSyncDate?.formatted(date: .omitted, time: .standard) ?? "Never"

        return HStack(spacing: DesignTokens.Spacing.sm) {
            kpiCard(title: "TOTAL EVENTS", value: "\(totalCount)", icon: "list.bullet.rectangle", color: DesignTokens.ink)
            kpiCard(title: "SUCCESS", value: "\(successCount)", icon: "checkmark.circle.fill", color: DesignTokens.secondary)
            kpiCard(title: "WARNINGS", value: "\(warningCount)", icon: "exclamationmark.triangle.fill", color: DesignTokens.tierOrange)
            kpiCard(title: "FAILURES", value: "\(failureCount)", icon: "xmark.circle.fill", color: DesignTokens.Colors.statusError)
            kpiCard(title: "LAST SYNC", value: lastSyncText, icon: "clock.arrow.circlepath", color: DesignTokens.primary, isMonospace: true)
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color, isMonospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.inkTertiary)
            }

            Text(value)
                .font(isMonospace ? .system(size: 14, weight: .semibold, design: .monospaced) : .system(size: 16, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Filters & Search
    private var filterAndSearchBar: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                SearchBarView(text: $searchText, placeholder: "Search by target, message, or details...")
                    .frame(maxWidth: 360)

                Spacer()

                // Status Chips
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    statusChip(title: "All", status: nil)
                    ForEach(SyncLogStatus.allCases, id: \.self) { status in
                        statusChip(title: status.title, status: status)
                    }
                }
            }

            // Category Selector
            HStack(spacing: DesignTokens.Spacing.xxs) {
                categoryChip(title: "All Categories", category: nil)
                ForEach(SyncLogCategory.allCases, id: \.self) { cat in
                    categoryChip(title: cat.title, category: cat)
                }
                Spacer()
                Text("\(filteredLogs.count) of \(state.syncHistory.count) entries")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.inkSecondary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private func statusChip(title: String, status: SyncLogStatus?) -> some View {
        let isSelected = selectedStatus == status
        return Button {
            selectedStatus = status
        } label: {
            HStack(spacing: 4) {
                if let status {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? DesignTokens.primaryContainer : DesignTokens.surfaceContainerLow)
            .foregroundStyle(isSelected ? Color.white : DesignTokens.ink)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? DesignTokens.primary : DesignTokens.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func categoryChip(title: String, category: SyncLogCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? DesignTokens.surfaceContainerHigh : DesignTokens.surfaceContainerLowest)
            .foregroundStyle(isSelected ? DesignTokens.ink : DesignTokens.inkSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? DesignTokens.secondary : DesignTokens.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logs List
    private var logsList: some View {
        LazyVStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(filteredLogs) { entry in
                logRow(for: entry)
            }
        }
    }

    private func logRow(for entry: SyncLogEntry) -> some View {
        let isExpanded = expandedEntryIds.contains(entry.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Main row header
            Button {
                withAnimation(DesignTokens.snappySpring) {
                    if isExpanded {
                        expandedEntryIds.remove(entry.id)
                    } else {
                        expandedEntryIds.insert(entry.id)
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    // Status icon & badge
                    HStack(spacing: 4) {
                        Image(systemName: entry.status.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(entry.status.color)
                        Text(entry.status.title)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(entry.status.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.status.backgroundColor)
                    .clipShape(Capsule())

                    // Timestamp
                    Text(entry.formattedTimestamp)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesignTokens.inkTertiary)

                    // Category pill
                    HStack(spacing: 3) {
                        Image(systemName: entry.category.icon)
                            .font(.caption2)
                        Text(entry.category.title)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.surfaceContainerHigh)
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .clipShape(Capsule())

                    // Target name
                    Text(entry.targetName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.ink)

                    // Message
                    Text(entry.message)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    // Duration
                    if let dur = entry.formattedDuration {
                        Text(dur)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.surfaceContainerLow)
                            .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded details block
            if isExpanded {
                Divider()
                    .padding(.horizontal, DesignTokens.Spacing.sm)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack {
                        Text("Time: \(entry.fullTimestamp)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(DesignTokens.inkTertiary)
                        if let dur = entry.formattedDuration {
                            Text("• Duration: \(dur)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(DesignTokens.inkTertiary)
                        }
                        Spacer()
                        Button {
                            copyEntry(entry)
                        } label: {
                            Label("Copy Entry", systemImage: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy this log entry to clipboard")
                    }

                    if let details = entry.details, !details.isEmpty {
                        Text(details)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignTokens.ink)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignTokens.surfaceContainerLow)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs))
                    }
                }
                .padding(DesignTokens.Spacing.sm)
                .background(DesignTokens.surfaceContainerLowest.opacity(0.5))
            }
        }
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm)
                .strokeBorder(isExpanded ? DesignTokens.secondary.opacity(0.4) : DesignTokens.cardBorder, lineWidth: 1)
        )
    }

    private var emptyHistoryView: some View {
        ContentUnavailableView {
            Label("No Logs Recorded", systemImage: "terminal")
        } description: {
            Text("Synchronization history is currently empty. Sync global or project resources to view detailed logs.")
        } actions: {
            Button("Sync All") {
                state.syncAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primaryContainer)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clipboard Helpers
    private func copyAllLogs() {
        let content = filteredLogs.map { entry in
            var line = "[\(entry.fullTimestamp)] [\(entry.status.rawValue)] [\(entry.category.rawValue)] \(entry.targetName): \(entry.message)"
            if let dur = entry.formattedDuration {
                line += " (\(dur))"
            }
            if let details = entry.details, !details.isEmpty {
                line += "\n  Details: \(details.replacingOccurrences(of: "\n", with: "\n  "))"
            }
            return line
        }.joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func copyEntry(_ entry: SyncLogEntry) {
        var text = "[\(entry.fullTimestamp)] [\(entry.status.rawValue)] [\(entry.category.rawValue)] \(entry.targetName): \(entry.message)"
        if let dur = entry.formattedDuration {
            text += " (\(dur))"
        }
        if let details = entry.details, !details.isEmpty {
            text += "\n\(details)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
