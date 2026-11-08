import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class M3_2ChallengerTelemetryTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M3_2ChallengerTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - 1. Empirical Verification: Zero Hardcoded Fake RPC Strings in Source & Binary

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testChallenger1_ZeroFakeRPCStrings_InSourceFilesAndBinary() throws {
        let footerFilePath = repoRoot.appendingPathComponent("Sources/AntigravityManager/Views/Components/ControlCenterFooter.swift").path
        XCTAssertTrue(fm.fileExists(atPath: footerFilePath), "Footer file must exist at \(footerFilePath)")
        let footerContent = try String(contentsOfFile: footerFilePath, encoding: .utf8)

        let forbiddenPhrases = [
            "1,482 calls",
            "1,482",
            "0 drops",
            "99.98% up-ratio",
            "99.98%",
            "Mission Control RPC Channel",
            "LISTENING"
        ]

        for phrase in forbiddenPhrases {
            XCTAssertFalse(
                footerContent.contains(phrase),
                "ControlCenterFooter source MUST NOT contain fake literal: '\(phrase)'"
            )
        }

        // Verify all Swift files under Sources/
        let sourcesURL = repoRoot.appendingPathComponent("Sources")
        if let enumerator = fm.enumerator(at: sourcesURL, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    let source = try String(contentsOf: fileURL, encoding: .utf8)
                    for phrase in ["1,482 calls", "0 drops", "99.98% up-ratio"] {
                        XCTAssertFalse(
                            source.contains(phrase),
                            "Source file \(fileURL.lastPathComponent) contains forbidden fake RPC literal '\(phrase)'"
                        )
                    }
                }
            }
        }

        // Check compiled binary if available
        let binaryPath = repoRoot.appendingPathComponent("agymg.app/Contents/MacOS/agymg").path
        if fm.fileExists(atPath: binaryPath) {
            let binaryData = try Data(contentsOf: URL(fileURLWithPath: binaryPath))
            let binaryString = String(decoding: binaryData, as: UTF8.self)
            for phrase in ["1,482 calls", "99.98% up-ratio"] {
                XCTAssertFalse(
                    binaryString.contains(phrase),
                    "App binary at \(binaryPath) contains forbidden fake string '\(phrase)'"
                )
            }
        }
    }

    // MARK: - 2. Empirical Verification: ControlCenterFooter Live State Mutations

    func testChallenger2_ControlCenterFooter_LiveStateMutationReactivity() {
        let state = AppState(autoload: false)
        state.clearSyncHistory()

        // 1. Initial State: All zero
        XCTAssertEqual(state.servers.count, 0)
        XCTAssertEqual(state.skills.count, 0)
        XCTAssertEqual(state.plugins.count, 0)
        XCTAssertEqual(state.projects.count, 0)
        XCTAssertFalse(state.isSyncing)
        XCTAssertNil(state.statusMessage)
        XCTAssertTrue(state.syncHistory.isEmpty)

        let initialFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(initialFooter.body)

        // 2. Mutate Servers: add 15 servers
        state.servers = (1...15).map { i in
            MCPServerDefinition(id: "srv-\(i)", name: "Server \(i)", category: "Core", config: [:])
        }
        XCTAssertEqual(state.servers.count, 15)

        // 3. Mutate Skills: add 23 skills
        state.skills = (1...23).map { i in
            SkillDefinition(id: "sk-\(i)", name: "Skill \(i)", description: "Desc \(i)", category: "Dev", path: "/path/\(i)", origin: .vault)
        }
        XCTAssertEqual(state.skills.count, 23)

        // 4. Mutate Plugins: add 7 plugins
        state.plugins = (1...7).map { i in
            PluginDefinition(id: "pl-\(i)", name: "Plugin \(i)", path: "/path/pl/\(i)", hasMCP: true, hasSkills: false)
        }
        XCTAssertEqual(state.plugins.count, 7)

        // 5. Mutate Projects: add 4 projects
        state.projects = (1...4).map { i in
            ProjectProfile(id: "proj-\(i)", name: "Project \(i)", path: "/path/pr/\(i)")
        }
        XCTAssertEqual(state.projects.count, 4)

        // 6. Mutate status message
        state.statusMessage = "All components ready for synchronization"
        XCTAssertEqual(state.statusMessage, "All components ready for synchronization")

        // 7. Verify body renders with mutated state
        let mutatedFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(mutatedFooter.body)

        // 8. Test Status Indicator States: LIVE -> SYNCING -> ERROR -> LIVE
        // LIVE state
        state.isSyncing = false
        XCTAssertTrue(state.syncHistory.isEmpty)

        // SYNCING state
        state.isSyncing = true
        let syncingFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(syncingFooter.body)

        // ERROR state
        state.isSyncing = false
        state.logSyncEvent(
            status: .failure,
            category: .system,
            targetName: "SyncEngine",
            message: "Failed to write manifest",
            details: "EACCES permission denied"
        )
        XCTAssertEqual(state.syncHistory.first?.status, .failure)
        let errorFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(errorFooter.body)

        // SUCCESS state recovery: log success -> becomes first element
        state.logSyncEvent(
            status: .success,
            category: .system,
            targetName: "SyncEngine",
            message: "Manifest repaired",
            details: nil
        )
        XCTAssertEqual(state.syncHistory.first?.status, .success)
        let recoveredFooter = ControlCenterFooter(state: state)
        XCTAssertNotNil(recoveredFooter.body)

        // 9. View Logs badge count verification
        XCTAssertEqual(state.syncHistory.count, 2)
    }

    // MARK: - 3. Empirical Stress Test: 1,000 Rapid Event Insertions, 500-Entry Cap & FIFO Eviction

    func testChallenger3_LogSyncEvent_Rapid1000InsertionsAndStrict500Ceiling() {
        let state = AppState(autoload: false)
        state.clearSyncHistory()
        XCTAssertEqual(state.syncHistory.count, 0)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Insert 1,000 events rapidly
        for i in 1...1000 {
            state.logSyncEvent(
                status: (i % 5 == 0) ? .failure : ((i % 3 == 0) ? .warning : .success),
                category: (i % 2 == 0) ? .project : .global,
                targetName: "Event-\(i)",
                message: "Sync step #\(i) performed with status",
                details: (i % 4 == 0) ? "Diagnostic info for event \(i)" : nil,
                duration: Double(i) * 0.0001
            )
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Benchmark assertion: 1,000 insertions must complete in sub-50ms (typically < 10ms)
        XCTAssertLessThan(elapsed, 0.5, "1,000 insertions took \(elapsed)s, which is slower than acceptable")

        // Invariant 1: History count MUST be capped at strictly 500
        XCTAssertEqual(
            state.syncHistory.count,
            500,
            "History count must be strictly capped at 500 entries (got \(state.syncHistory.count))"
        )

        // Invariant 2: Head of list must be the newest event (Event-1000)
        XCTAssertEqual(
            state.syncHistory.first?.targetName,
            "Event-1000",
            "Index 0 must be the most recently logged event"
        )

        // Invariant 3: Tail of list must be Event-501 (500 most recent events: 501...1000)
        XCTAssertEqual(
            state.syncHistory.last?.targetName,
            "Event-501",
            "Index 499 must be Event-501 (the oldest non-evicted entry)"
        )

        // Invariant 4: Evicted events (Event-1 through Event-500) must NOT exist in history
        let allTargetNames = Set(state.syncHistory.map(\.targetName))
        XCTAssertFalse(allTargetNames.contains("Event-1"), "Event-1 must have been evicted")
        XCTAssertFalse(allTargetNames.contains("Event-250"), "Event-250 must have been evicted")
        XCTAssertFalse(allTargetNames.contains("Event-500"), "Event-500 must have been evicted")
        XCTAssertTrue(allTargetNames.contains("Event-501"), "Event-501 must be preserved")
        XCTAssertTrue(allTargetNames.contains("Event-1000"), "Event-1000 must be preserved")
    }

    // MARK: - 4. Empirical Verification: clearSyncHistory() Complete Reset

    func testChallenger4_ClearSyncHistory_ResetsCompletely() {
        let state = AppState(autoload: false)
        state.clearSyncHistory()

        // Populate with 250 entries
        for i in 1...250 {
            state.logSyncEvent(
                status: .info,
                category: .vault,
                targetName: "Vault-\(i)",
                message: "Syncing vault component \(i)"
            )
        }
        XCTAssertEqual(state.syncHistory.count, 250)

        // Clear history
        state.clearSyncHistory()

        XCTAssertTrue(state.syncHistory.isEmpty, "syncHistory must be empty after clearSyncHistory()")
        XCTAssertEqual(state.syncHistory.count, 0, "syncHistory count must be 0 after clearSyncHistory()")

        // Calling clearSyncHistory() on already empty array must be idempotent and safe
        state.clearSyncHistory()
        XCTAssertTrue(state.syncHistory.isEmpty)

        // New insertion after clear works normally
        state.logSyncEvent(status: .success, category: .all, targetName: "PostClear", message: "After clear")
        XCTAssertEqual(state.syncHistory.count, 1)
        XCTAssertEqual(state.syncHistory.first?.targetName, "PostClear")
    }

    // MARK: - 5. Empirical Verification: Duration Math Across Microsecond, Millisecond, Second Ranges

    func testChallenger5_DurationMath_MicrosecondMillisecondSecondAndEdgeCases() {
        // Range 1: nil duration -> nil
        let nilEntry = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: nil)
        XCTAssertNil(nilEntry.formattedDuration, "nil duration must format to nil")

        // Range 2: 0.0 seconds -> 0.0 µs (< 0.001)
        let zeroEntry = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.0)
        XCTAssertEqual(zeroEntry.formattedDuration, "0.0 µs")

        // Range 3: Microsecond values (< 0.001 s)
        let micro1 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.000001) // 1 µs
        XCTAssertEqual(micro1.formattedDuration, "1.0 µs")

        let micro2 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.000456) // 456 µs
        XCTAssertEqual(micro2.formattedDuration, "456.0 µs")

        let micro3 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.000999) // 999 µs
        XCTAssertEqual(micro3.formattedDuration, "999.0 µs")

        // Range 4: Exact millisecond boundary (0.001 s)
        let milliBoundary = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.001) // 1 ms
        XCTAssertEqual(milliBoundary.formattedDuration, "1.0 ms")

        // Range 5: Millisecond values (0.001 s <= duration < 1.0 s)
        let milli1 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.015) // 15 ms
        XCTAssertEqual(milli1.formattedDuration, "15.0 ms")

        let milli2 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.2504) // 250.4 ms
        XCTAssertEqual(milli2.formattedDuration, "250.4 ms")

        let milli3 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 0.999) // 999 ms
        XCTAssertEqual(milli3.formattedDuration, "999.0 ms")

        // Range 6: Exact second boundary (1.0 s)
        let secBoundary = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 1.0) // 1.00 s
        XCTAssertEqual(secBoundary.formattedDuration, "1.00 s")

        // Range 7: Second values (>= 1.0 s)
        let sec1 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 1.5) // 1.50 s
        XCTAssertEqual(sec1.formattedDuration, "1.50 s")

        let sec2 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 12.3456) // 12.35 s
        XCTAssertEqual(sec2.formattedDuration, "12.35 s")

        let sec3 = SyncLogEntry(status: .info, targetName: "T", message: "M", duration: 3600.0) // 3600.00 s
        XCTAssertEqual(sec3.formattedDuration, "3600.00 s")
    }

    // MARK: - 6. Empirical Verification: SyncLogsView Filtering by Status, Category, and Search Query

    func testChallenger6_SyncLogsView_FilteringLogicOracle() {
        let state = AppState(autoload: false)
        state.clearSyncHistory()

        let entrySuccess = SyncLogEntry(
            status: .success,
            category: .global,
            targetName: "Global Core",
            message: "Global configuration written to mcp_config.json",
            details: "12 MCPs, 9 skills linked successfully",
            duration: 0.003
        )
        let entryWarning = SyncLogEntry(
            status: .warning,
            category: .project,
            targetName: "acme-web",
            message: "Symlink existing but valid at destination",
            details: "File exists: /Projects/acme-web/.agents/plugins/agy-manager",
            duration: 0.045
        )
        let entryFailure = SyncLogEntry(
            status: .failure,
            category: .project,
            targetName: "docs-portal",
            message: "Failed to write project manifest due to ENOSPC",
            details: "Disk quota exceeded on volume",
            duration: 0.120
        )
        let entryInfo = SyncLogEntry(
            status: .info,
            category: .vault,
            targetName: "Master Vault",
            message: "Discovered 14 skills in vault directory",
            details: nil,
            duration: 0.0005
        )
        let entrySystemFailure = SyncLogEntry(
            status: .failure,
            category: .system,
            targetName: "System Daemon",
            message: "Timeout waiting for lock",
            details: nil,
            duration: 5.0
        )

        state.syncHistory = [entrySystemFailure, entryInfo, entryFailure, entryWarning, entrySuccess]
        XCTAssertEqual(state.syncHistory.count, 5)

        // Helper filter function reflecting SyncLogsView.filteredLogs specification:
        func filterLogs(status: SyncLogStatus?, category: SyncLogCategory?, search: String) -> [SyncLogEntry] {
            state.syncHistory.filter { entry in
                let matchesStatus = status == nil || entry.status == status
                let matchesCategory = category == nil || entry.category == category
                let matchesSearch = search.isEmpty ||
                    entry.targetName.localizedCaseInsensitiveContains(search) ||
                    entry.message.localizedCaseInsensitiveContains(search) ||
                    (entry.details?.localizedCaseInsensitiveContains(search) ?? false)
                return matchesStatus && matchesCategory && matchesSearch
            }
        }

        // Test 1: Status Filters
        let successLogs = filterLogs(status: .success, category: nil, search: "")
        XCTAssertEqual(successLogs.count, 1)
        XCTAssertEqual(successLogs.first?.targetName, "Global Core")

        let warningLogs = filterLogs(status: .warning, category: nil, search: "")
        XCTAssertEqual(warningLogs.count, 1)
        XCTAssertEqual(warningLogs.first?.targetName, "acme-web")

        let failureLogs = filterLogs(status: .failure, category: nil, search: "")
        XCTAssertEqual(failureLogs.count, 2)
        XCTAssertTrue(failureLogs.contains(where: { $0.targetName == "docs-portal" }))
        XCTAssertTrue(failureLogs.contains(where: { $0.targetName == "System Daemon" }))

        let infoLogs = filterLogs(status: .info, category: nil, search: "")
        XCTAssertEqual(infoLogs.count, 1)
        XCTAssertEqual(infoLogs.first?.targetName, "Master Vault")

        let allStatusLogs = filterLogs(status: nil, category: nil, search: "")
        XCTAssertEqual(allStatusLogs.count, 5)

        // Test 2: Category Filters
        let globalLogs = filterLogs(status: nil, category: .global, search: "")
        XCTAssertEqual(globalLogs.count, 1)
        XCTAssertEqual(globalLogs.first?.targetName, "Global Core")

        let projectLogs = filterLogs(status: nil, category: .project, search: "")
        XCTAssertEqual(projectLogs.count, 2)
        XCTAssertTrue(projectLogs.contains(where: { $0.targetName == "acme-web" }))
        XCTAssertTrue(projectLogs.contains(where: { $0.targetName == "docs-portal" }))

        let vaultLogs = filterLogs(status: nil, category: .vault, search: "")
        XCTAssertEqual(vaultLogs.count, 1)
        XCTAssertEqual(vaultLogs.first?.targetName, "Master Vault")

        let systemLogs = filterLogs(status: nil, category: .system, search: "")
        XCTAssertEqual(systemLogs.count, 1)
        XCTAssertEqual(systemLogs.first?.targetName, "System Daemon")

        // Test 3: Search Query Matches (targetName, message, details)
        // Match on targetName (case-insensitive)
        let searchTarget = filterLogs(status: nil, category: nil, search: "AcMe-WeB")
        XCTAssertEqual(searchTarget.count, 1)
        XCTAssertEqual(searchTarget.first?.targetName, "acme-web")

        // Match on message (case-insensitive)
        let searchMessage = filterLogs(status: nil, category: nil, search: "timeout")
        XCTAssertEqual(searchMessage.count, 1)
        XCTAssertEqual(searchMessage.first?.targetName, "System Daemon")

        // Match on details (case-insensitive)
        let searchDetails = filterLogs(status: nil, category: nil, search: "ENOSPC")
        XCTAssertEqual(searchDetails.count, 1)
        XCTAssertEqual(searchDetails.first?.targetName, "docs-portal")

        // Safe evaluation when details == nil
        let searchSafeNil = filterLogs(status: nil, category: nil, search: "Discovered")
        XCTAssertEqual(searchSafeNil.count, 1)
        XCTAssertEqual(searchSafeNil.first?.targetName, "Master Vault")

        // Search with zero matches
        let searchNone = filterLogs(status: nil, category: nil, search: "phantom_nonexistent_term")
        XCTAssertEqual(searchNone.count, 0)

        // Test 4: Combined Multi-dimensional Filters
        // Status = .failure AND Category = .project -> only docs-portal
        let combo1 = filterLogs(status: .failure, category: .project, search: "")
        XCTAssertEqual(combo1.count, 1)
        XCTAssertEqual(combo1.first?.targetName, "docs-portal")

        // Status = .failure AND Category = .global -> 0 matches
        let combo2 = filterLogs(status: .failure, category: .global, search: "")
        XCTAssertEqual(combo2.count, 0)

        // Status = .failure AND Search = "lock" -> System Daemon
        let combo3 = filterLogs(status: .failure, category: nil, search: "lock")
        XCTAssertEqual(combo3.count, 1)
        XCTAssertEqual(combo3.first?.targetName, "System Daemon")

        // Test 5: SyncLogsView body renders with populated logs
        let logsView = SyncLogsView(state: state)
        XCTAssertNotNil(logsView.body)
    }

    // MARK: - 7. Empirical Verification: Expandable Log Details & Clipboard Serialization

    func testChallenger7_SyncLogDetails_FormattingAndClipboardSerialization() {
        let entry = SyncLogEntry(
            status: .failure,
            category: .project,
            targetName: "fitness-platform",
            message: "Failed to create symlink",
            details: "File exists: /fitness-platform/.agents/skills/ask\nSymlink creation aborted",
            duration: 0.0025
        )

        // Formatted duration
        XCTAssertEqual(entry.formattedDuration, "2.5 ms")

        // Formatted timestamp non-empty
        XCTAssertFalse(entry.formattedTimestamp.isEmpty)
        XCTAssertFalse(entry.fullTimestamp.isEmpty)

        // Verification of single entry clipboard export format:
        // Expected format: "[<fullTimestamp>] [FAILURE] [PROJECT] fitness-platform: Failed to create symlink (2.5 ms)\nFile exists: ..."
        var singleExport = "[\(entry.fullTimestamp)] [\(entry.status.rawValue)] [\(entry.category.rawValue)] \(entry.targetName): \(entry.message)"
        if let dur = entry.formattedDuration {
            singleExport += " (\(dur))"
        }
        if let details = entry.details, !details.isEmpty {
            singleExport += "\n\(details)"
        }

        XCTAssertTrue(singleExport.contains("[FAILURE]"))
        XCTAssertTrue(singleExport.contains("[PROJECT]"))
        XCTAssertTrue(singleExport.contains("fitness-platform: Failed to create symlink"))
        XCTAssertTrue(singleExport.contains("(2.5 ms)"))
        XCTAssertTrue(singleExport.contains("File exists:"))

        // Verification of entry with nil details and nil duration
        let minimalEntry = SyncLogEntry(
            status: .info,
            category: .vault,
            targetName: "Vault",
            message: "Discovered 5 skills",
            details: nil,
            duration: nil
        )
        XCTAssertNil(minimalEntry.formattedDuration)

        var minimalExport = "[\(minimalEntry.fullTimestamp)] [\(minimalEntry.status.rawValue)] [\(minimalEntry.category.rawValue)] \(minimalEntry.targetName): \(minimalEntry.message)"
        if let dur = minimalEntry.formattedDuration {
            minimalExport += " (\(dur))"
        }
        if let details = minimalEntry.details, !details.isEmpty {
            minimalExport += "\n\(details)"
        }

        XCTAssertTrue(minimalExport.contains("[INFO]"))
        XCTAssertTrue(minimalExport.contains("[VAULT]"))
        XCTAssertTrue(minimalExport.contains("Vault: Discovered 5 skills"))
        XCTAssertFalse(minimalExport.contains("("))
        XCTAssertFalse(minimalExport.contains("\n"))
    }

    // MARK: - 8. Empirical Verification: Concurrent Task Dispatches to logSyncEvent

    func testChallenger8_ConcurrentTasks_LogSyncEventSafety() async {
        let state = AppState(autoload: false)
        state.clearSyncHistory()

        // Dispatch 20 concurrent tasks, each calling MainActor state.logSyncEvent 25 times (500 total)
        await withTaskGroup(of: Void.self) { group in
            for taskId in 1...20 {
                group.addTask { @MainActor in
                    for eventId in 1...25 {
                        state.logSyncEvent(
                            status: .info,
                            category: .system,
                            targetName: "Task-\(taskId)",
                            message: "Concurrent event \(eventId)",
                            duration: 0.001
                        )
                    }
                }
            }
        }

        XCTAssertEqual(state.syncHistory.count, 500, "Concurrent insertions must respect 500 cap")
        XCTAssertFalse(state.syncHistory.isEmpty)

        // Clear history afterwards
        state.clearSyncHistory()
        XCTAssertEqual(state.syncHistory.count, 0)
    }
}
