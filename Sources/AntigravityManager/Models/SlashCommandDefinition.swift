import Foundation

public struct SlashCommandDefinition: Identifiable, Sendable {
    public var id: String { command }
    public var command: String
    public var name: String
    public var description: String
    public var category: String
    public var fullProtocol: String

    public init(
        command: String,
        name: String,
        description: String,
        category: String = "Core",
        fullProtocol: String? = nil
    ) {
        self.command = command
        self.name = name
        self.description = description
        self.category = category
        self.fullProtocol = fullProtocol ?? description
    }

    public static let standardCommands: [SlashCommandDefinition] = [
        SlashCommandDefinition(
            command: "/plan",
            name: "Implementation Plan",
            description: "Deep research and step-by-step technical plan before making any code modifications. Creates an implementation plan artifact for review.",
            category: "Workflow",
            fullProtocol: """
            ### 1. Strict Read-Only Research Phase
            The agent MUST NOT modify files, create code, or run mutating shell commands until the user clicks "Proceed" or explicitly approves the plan in chat.

            ### 2. Deep Research & Progress Updates
            - Before drafting the plan, the agent thoroughly inspects the codebase (searching symbols, reading configs, analyzing dependencies).
            - During research, the agent shares concise status updates so the user can follow the investigation in real time.

            ### 3. Interactive Plan Artifact (implementation_plan.md)
            The plan is generated as a structured Markdown artifact containing:
            - **Goal Description**: Concise problem statement, context, and target outcome.
            - **User Review Required**: Highlighted breaking changes or key architectural trade-offs.
            - **Open Questions**: Targeted questions for the user before implementation begins.
            - **Proposed Changes**: File-by-file breakdown grouped by component with [NEW], [MODIFY], [DELETE] markers.
            - **Verification Plan**: Exact automated test commands and manual verification steps.
            - **RequestFeedback**: Set to true to render an interactive "Proceed" button.

            ### 4. Verification & Walkthrough (walkthrough.md)
            After implementation, the agent runs the test suite and produces a walkthrough summarizing changes and verification evidence.
            """
        ),
        SlashCommandDefinition(
            command: "/ask",
            name: "Read-Only Deep Q&A",
            description: "Answers user questions concisely and directly based on deep context synthesis, strictly prohibiting any file modifications.",
            category: "Consultation",
            fullProtocol: """
            ### 1. Strict Read-Only Mode
            Strictly prohibits calling file-editing tools (replace_file_content, write_to_file) or mutating terminal commands (git push, deploy, migrations). Only inspection and read tools are permitted.

            ### 2. Deep Context Synthesis
            Synthesizes the full session context before answering:
            - System architecture (frontend, backend, database, macOS/Swift, MCP servers).
            - Prior user requirements, corrections, and engineering preferences.
            - Technical constraints and earlier design decisions.

            ### 3. Communication Style
            - Direct, high-signal engineering answers with zero conversational filler.
            - Clickable file:// links for all referenced files and code symbols.
            """
        ),
        SlashCommandDefinition(
            command: "/goal",
            name: "Autonomous Goal Mode",
            description: "Runs long-running or overnight tasks autonomously without stopping until the goal is fully accomplished.",
            category: "Workflow",
            fullProtocol: """
            ### 1. Unattended Autonomous Execution
            The agent enters full autonomy mode and continues iterating until the target objective is completely achieved.

            ### 2. Self-Debugging & Repair Loops
            - When builds or tests fail, the agent inspects stack traces, identifies root causes, and fixes them autonomously.
            - Does not pause to ask permission for routine intermediate steps or minor build issues.

            ### 3. Completion Criteria
            Stops only when all requirements are satisfied and verified by automated tests, or when blocked by an external dependency (such as a missing API credential).
            """
        ),
        SlashCommandDefinition(
            command: "/browser",
            name: "Browser & Web Search",
            description: "Interacts with web applications, searches online documentation, or inspects live pages.",
            category: "Research",
            fullProtocol: """
            ### 1. Web Automation & Documentation Lookup
            Searches online documentation, API references, or inspects running local development servers.

            ### 2. Retrieval Modes
            - **read_url_content**: Low-latency HTTP fetch converting static HTML to Markdown without JavaScript execution (ideal for docs and GitHub).
            - **Interactive browser**: Full browser rendering for dynamic SPAs, JavaScript flows, and visual UI verification.
            """
        ),
        SlashCommandDefinition(
            command: "/schedule",
            name: "Background Scheduler",
            description: "Schedules recurring cron jobs or one-off reminders in the background.",
            category: "Automation",
            fullProtocol: """
            ### 1. Background Timers & Cron Jobs
            Schedules one-shot timers (DurationSeconds) or recurring cron schedules (CronExpression, e.g. */5 * * * *).

            ### 2. Wakeup Conditions (TimerCondition)
            - **never**: Fires strictly after the specified duration elapses.
            - **any**: Cancels early when any message arrives from a subagent or background task.
            - **sender-id**: Waits for a specific background task or subagent.
            - **IsDaemon**: Keeps firing in the background even after the current task finishes.
            """
        ),
        SlashCommandDefinition(
            command: "/boost",
            name: "Deep Reasoning & Boost",
            description: "Engages deep multi-perspective reasoning and rigorous planning for difficult engineering problems.",
            category: "Workflow",
            fullProtocol: """
            ### 1. Maximum Engineering Rigor
            Engages slow, methodical reasoning for high-risk refactors, migrations, concurrency bugs, and architectural decisions.

            ### 2. Competing Hypotheses & Trade-offs
            - Never trusts the first idea; compares at least two viable approaches (Option A vs Option B) across performance, complexity, and maintainability.
            - Explicitly traces edge cases, failure modes, security boundaries, and race conditions before writing code.
            """
        ),
        SlashCommandDefinition(
            command: "/teamwork-preview",
            name: "Multi-Agent Swarm",
            description: "Orchestrates multi-agent teams for large autonomous tasks and batch refactoring.",
            category: "Multi-Agent",
            fullProtocol: """
            ### 1. Multi-Agent Swarm Coordination
            Spawns specialized autonomous subagents in parallel (e.g., frontend, backend, and verification workers).

            ### 2. Isolated Workspaces
            - Subagents operate in isolated or shared workspaces without clobbering concurrent edits.
            - Reactive wakeup notifies the coordinator as soon as workers finish without polling loops.

            ### 3. Review & Consolidation
            The coordinator audits worker outputs, resolves conflicts, and verifies the integrated result.
            """
        ),
        SlashCommandDefinition(
            command: "/grill-me",
            name: "Architectural Interview",
            description: "Conducts an interactive technical interview to interrogate assumptions and align design decisions.",
            category: "Consultation",
            fullProtocol: """
            ### 1. Pre-Implementation Design Review
            Acts as a rigorous Staff/Principal engineer challenging assumptions before any code is written.

            ### 2. Structured Questioning (ask_question)
            - Asks targeted questions covering data models, failure modes, security boundaries, and scope.
            - Eliminates ambiguity and surfaces hidden edge cases upfront.
            """
        ),
        SlashCommandDefinition(
            command: "/skill-creator",
            name: "Skill Creator",
            description: "Interactive builder for creating, structuring, and registering new Antigravity skills into Vault or projects.",
            category: "Customization",
            fullProtocol: """
            ### 1. Skill Package Architecture
            Interactive builder for standard SKILL.md packages:
            - Generates SKILL.md with YAML frontmatter (name, description) and clear trigger rules.
            - Organizes optional folders: scripts/ for helpers, references/ for docs, examples/ for sample code.

            ### 2. Registration & Discovery
            Installs into a local project (.agents/skills/<name>) or the central Master Vault (~/.gemini/manager-vault/skills/<name>).
            """
        ),
        SlashCommandDefinition(
            command: "/compact",
            name: "Context Compaction",
            description: "Summarizes and compacts long conversation history to free up model context window.",
            category: "Maintenance",
            fullProtocol: """
            ### 1. Context Window Compaction
            Compacts long session histories to reclaim context window capacity and maintain sharp reasoning.

            ### 2. Critical State Preservation
            Retains architectural decisions, modified file paths, open tasks, and constraints while pruning verbose logs and intermediate diffs.
            """
        ),
        SlashCommandDefinition(
            command: "/learn",
            name: "Rule & Behavior Extraction",
            description: "Persists corrected agent behaviors or environment solutions for future sessions.",
            category: "Customization",
            fullProtocol: """
            ### 1. Persistent Rule Extraction
            Captures user corrections or environment-specific lessons so they do not need to be repeated in future sessions.

            ### 2. Rule Storage
            Writes concise engineering rules into AGENTS.md, GEMINI.md, or .agents/rules/*.md so both Claude Code and Antigravity inherit them automatically.
            """
        )
    ]
}
