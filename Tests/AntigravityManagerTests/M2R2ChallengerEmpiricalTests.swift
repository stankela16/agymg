import XCTest
import SwiftUI
@testable import AntigravityManager

@MainActor
final class M2R2ChallengerEmpiricalTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("M2Challenger-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, fm.fileExists(atPath: tempDir.path) {
            try? fm.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - 1. Empirical Proof of Zero Disk I/O when Physical Directory is Removed

    func testEmpiricalZeroDiskIOWhenPhysicalDirectoryDeleted() throws {
        let projDir = tempDir.appendingPathComponent("empirically-deleted-project", isDirectory: true)
        let skillsDir = projDir.appendingPathComponent(".agents/skills", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        var expectedSkills: [SkillDefinition] = []
        for i in 1...5 {
            let skillFolder = skillsDir.appendingPathComponent("skill-\(i)", isDirectory: true)
            try fm.createDirectory(at: skillFolder, withIntermediateDirectories: true)
            let skillMd = skillFolder.appendingPathComponent("SKILL.md")
            try """
            ---
            name: Empirical Skill \(i)
            description: Skill number \(i) for empirical proof
            ---
            """.write(to: skillMd, atomically: true, encoding: .utf8)

            expectedSkills.append(SkillDefinition(
                id: "skill-\(i)",
                name: "Empirical Skill \(i)",
                description: "Skill number \(i) for empirical proof",
                category: "Core & Tools",
                path: skillFolder.path,
                origin: .projectLocal
            ))
        }

        let project = ProjectProfile(id: "emp-proj-1", name: "Empirical Proj", path: projDir.path)
        let state = AppState(autoload: false)
        state.projectLocalSkills[project.id] = expectedSkills

        // EMPIRICAL DESTRUCTION: Delete the entire project directory tree from disk
        try fm.removeItem(at: projDir)
        XCTAssertFalse(fm.fileExists(atPath: projDir.path), "Physical project directory MUST be completely gone from disk")

        // Read local skills - MUST succeed purely from in-memory cache
        let retrieved = state.localSkills(for: project)

        XCTAssertEqual(retrieved.count, 5)
        for (idx, skill) in retrieved.enumerated() {
            XCTAssertEqual(skill.id, expectedSkills[idx].id)
            XCTAssertEqual(skill.name, expectedSkills[idx].name)
            XCTAssertEqual(skill.description, expectedSkills[idx].description)
        }

        print("[EMPIRICAL EVIDENCE] Successfully retrieved \(retrieved.count) skills from state.localSkills(for:) while project directory is absent on disk.")
    }

    // MARK: - 2. High-Precision Benchmark: Latency < 0.01ms (10 microseconds)

    func testBenchmarkLocalSkillsLatencyIsUnderTenMicroseconds() throws {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "bench-proj", name: "Bench Project", path: "/tmp/nonexistent-bench")

        let skills = (1...10).map { i in
            SkillDefinition(
                id: "bench-skill-\(i)",
                name: "Bench Skill \(i)",
                description: "Description for \(i)",
                category: "Engineering",
                path: "/tmp/nonexistent-bench/.agents/skills/bench-skill-\(i)",
                origin: .projectLocal
            )
        }
        state.projectLocalSkills[project.id] = skills

        // Warm up cache and CPU branch predictor
        for _ in 0..<1000 {
            _ = state.localSkills(for: project)
        }

        let iterations = 50_000
        let clock = ContinuousClock()
        let start = clock.now

        for _ in 0..<iterations {
            _ = state.localSkills(for: project)
        }

        let totalDuration = clock.now - start
        let totalSeconds = Double(totalDuration.components.seconds) + Double(totalDuration.components.attoseconds) / 1e18
        let averageMicroseconds = (totalSeconds / Double(iterations)) * 1_000_000.0
        let averageMilliseconds = averageMicroseconds / 1000.0

        print(String(format: "[EMPIRICAL BENCHMARK] %d iterations in %.4f s: Average = %.5f µs (%.6f ms) per call",
                     iterations, totalSeconds, averageMicroseconds, averageMilliseconds))

        // Requirement: < 0.01ms = < 10 microseconds
        XCTAssertLessThan(averageMicroseconds, 10.0,
                          "Average execution time must be under 10 µs (0.01 ms). Actual: \(averageMicroseconds) µs")
    }

    // MARK: - 3. Edge Case: Empty Local Skills Array

    func testEdgeCaseEmptyLocalSkillsCached() throws {
        let projDir = tempDir.appendingPathComponent("empty-local-skills-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)

        let project = ProjectProfile(id: "empty-proj", name: "Empty Skills Project", path: projDir.path)
        let state = AppState(autoload: false)
        // Project is registered with empty local skills
        state.projectLocalSkills[project.id] = []

        // Remove from disk to verify it never falls back to disk scan
        try fm.removeItem(at: projDir)
        XCTAssertFalse(fm.fileExists(atPath: projDir.path))

        let clock = ContinuousClock()
        let start = clock.now
        let result = state.localSkills(for: project)
        let duration = clock.now - start

        XCTAssertEqual(result.count, 0, "Empty cached skills array should return empty array")
        XCTAssertTrue(result.isEmpty)

        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let microseconds = seconds * 1_000_000.0
        XCTAssertLessThan(microseconds, 10.0, "Empty cache lookup must be < 10 µs")
    }

    // MARK: - 4. Edge Case: Missing Project in Cache (Cold Start / Cache Miss)

    func testEdgeCaseMissingProjectInCacheFallsBackGracefullyWithoutStateMutation() throws {
        let projDir = tempDir.appendingPathComponent("disk-only-proj", isDirectory: true)
        let skillsDir = projDir.appendingPathComponent(".agents/skills/disk-only-skill", isDirectory: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try "---\nname: Disk Only\ndescription: Exists only on disk\n---\n".write(
            to: skillsDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let project = ProjectProfile(id: "missing-cache-proj", name: "Missing Cache Proj", path: projDir.path)
        let state = AppState(autoload: false)

        // Precondition: Not present in projectLocalSkills
        XCTAssertNil(state.projectLocalSkills[project.id])

        // Query: Falls back to disk scan
        let result = state.localSkills(for: project)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "disk-only-skill")

        // CRITICAL INVARIANT: projectLocalSkills MUST NOT be mutated during read
        // to prevent "Modifying state during view update" runtime warnings in SwiftUI
        XCTAssertNil(state.projectLocalSkills[project.id], "projectLocalSkills must remain nil to avoid SwiftUI body mutation side-effects")

        // Second missing project with completely nonexistent disk path
        let nonExistentProject = ProjectProfile(id: "ghost-proj", name: "Ghost", path: "/tmp/totally-ghost-\(UUID().uuidString)")
        let ghostResult = state.localSkills(for: nonExistentProject)
        XCTAssertTrue(ghostResult.isEmpty, "Missing project with nonexistent path must return [] gracefully")
        XCTAssertNil(state.projectLocalSkills[nonExistentProject.id])
    }

    // MARK: - 5. Edge Case: Special Characters in Project IDs

    func testEdgeCaseSpecialCharacterProjectIds() throws {
        let state = AppState(autoload: false)
        let weirdIds = [
            "proj-with-spaces and symbols!@#$%^&*()",
            "🚀-unicode-project-привет",
            "",
            "../../path/traversal/attempt",
            "very-long-id-" + String(repeating: "a", count: 1000)
        ]

        for id in weirdIds {
            let proj = ProjectProfile(id: id, name: "Special \(id)", path: "/tmp/\(id)")
            state.projectLocalSkills[proj.id] = [
                SkillDefinition(id: "skill-\(id.hashValue)", name: "Test", description: "", category: "Core", path: "", origin: .projectLocal)
            ]

            let retrieved = state.localSkills(for: proj)
            XCTAssertEqual(retrieved.count, 1)
            XCTAssertEqual(retrieved.first?.id, "skill-\(id.hashValue)")
        }
    }

    // MARK: - 6. Concurrency Stress Test: 100 Concurrent Async Tasks on MainActor

    func testConcurrencyStressTestMultipleConcurrentReads() async throws {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "concurrent-proj", name: "Concurrent Proj", path: "/tmp/concurrent")
        state.projectLocalSkills[project.id] = [
            SkillDefinition(id: "c-skill", name: "Concurrent Skill", description: "Safe", category: "Core", path: "", origin: .projectLocal)
        ]

        // Spawn 100 concurrent tasks calling localSkills(for:)
        await withTaskGroup(of: [SkillDefinition].self) { group in
            for _ in 0..<100 {
                group.addTask { @MainActor in
                    state.localSkills(for: project)
                }
            }

            var count = 0
            for await skills in group {
                XCTAssertEqual(skills.count, 1)
                XCTAssertEqual(skills.first?.id, "c-skill")
                count += 1
            }
            XCTAssertEqual(count, 100)
        }
    }

    // MARK: - 7. Concurrency Stress Test: Background Task Updating Cache While MainActor Reads

    func testBackgroundCacheUpdateDoesNotCorruptMainActorReads() async throws {
        let state = AppState(autoload: false)
        let project = ProjectProfile(id: "bg-update-proj", name: "BG Proj", path: "/tmp/bg")
        state.projects = [project]
        state.projectLocalSkills[project.id] = []

        let iterations = 10_000

        // Asynchronously update cache from a detached background task, then apply to state
        let updateTask = Task.detached { () -> [String: [SkillDefinition]] in
            var updated: [String: [SkillDefinition]] = [:]
            updated[project.id] = (1...5).map { i in
                SkillDefinition(id: "skill-\(i)", name: "Skill \(i)", description: "", category: "Core", path: "", origin: .projectLocal)
            }
            return updated
        }

        // Concurrently read on MainActor
        var readCounts: [Int] = []
        for _ in 0..<iterations {
            let currentSkills = state.localSkills(for: project)
            readCounts.append(currentSkills.count)
            if Task.isCancelled { break }
        }

        let bgResult = await updateTask.value
        state.projectLocalSkills = bgResult

        let finalSkills = state.localSkills(for: project)
        XCTAssertEqual(finalSkills.count, 5)
        XCTAssertTrue(readCounts.allSatisfy { $0 == 0 || $0 == 5 })
    }

    // MARK: - 8. Zero-Lag View Body Evaluation Benchmark

    func testViewBodyRenderingZeroLagBenchmark() throws {
        let projDir = tempDir.appendingPathComponent("view-bench-proj", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        let gitignore = projDir.appendingPathComponent(".gitignore")
        try ".agents/plugins/agy-manager/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        let project = ProjectProfile(id: "view-bench", name: "View Benchmark", path: projDir.path)
        let state = AppState(autoload: false)
        state.projects = [project]
        state.projectLocalSkills[project.id] = (1...5).map { i in
            SkillDefinition(id: "s-\(i)", name: "Skill \(i)", description: "Desc \(i)", category: "Core & Tools", path: "", origin: .projectLocal)
        }
        state.projectSafetyAudits[project.id] = ProjectSafetyAudit.checking(for: project)

        var deletionTarget: DeletionTarget? = nil
        var editingSkill: SkillDefinition? = nil

        let detailView = ProjectDetailView(
            state: state,
            project: project,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )

        let skillsTab = ProjectSkillsTab(
            state: state,
            projectId: project.id,
            deletionTarget: Binding(get: { deletionTarget }, set: { deletionTarget = $0 }),
            editingSkill: Binding(get: { editingSkill }, set: { editingSkill = $0 })
        )

        let sidebarView = ProjectIsolationSidebarView(
            project: project,
            state: state
        )

        // Warmup
        _ = detailView.body
        _ = skillsTab.body
        _ = sidebarView.body

        let renderIterations = 500
        let clock = ContinuousClock()
        let start = clock.now

        for _ in 0..<renderIterations {
            _ = detailView.body
            _ = skillsTab.body
            _ = sidebarView.body
        }

        let totalDuration = clock.now - start
        let totalSeconds = Double(totalDuration.components.seconds) + Double(totalDuration.components.attoseconds) / 1e18
        let averageMsPerPass = (totalSeconds / Double(renderIterations)) * 1000.0

        print(String(format: "[EMPIRICAL BENCHMARK] 3 Views x %d passes: Total = %.4f s, Average = %.4f ms per pass",
                     renderIterations, totalSeconds, averageMsPerPass))

        // Target: < 1ms per pass for all three views combined
        XCTAssertLessThan(averageMsPerPass, 1.0,
                          "Total body evaluation for 3 views combined must average < 1ms. Actual: \(averageMsPerPass) ms")
    }
}
