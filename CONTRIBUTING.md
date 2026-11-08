# Contributing to `agymg`

Thank you for helping improve `agymg`! Below is everything you need to build, test, and submit pull requests cleanly.

## Prerequisites

- **macOS 14.0 (Sonoma)** or newer (`arm64` or `x86_64`)
- **Swift 6.0+** (Xcode 16+ or Xcode Command Line Tools: `xcode-select --install`)

No external dependencies, Ruby gems, Node packages, or paid Apple Developer certificates are required. `agymg` uses zero third-party Swift packages.

## Local Development

1. **Clone the repository**:
   ```bash
   git clone https://github.com/stankela16/agymg.git
   cd agymg
   ```

2. **Run the test suite** (sandboxed via `PathConstants.isRunningUnderTests` — never modifies your real `~/.gemini` or `~/.claude.json`):
   ```bash
   swift test
   ```

3. **Build with Swift 6 strict concurrency**:
   ```bash
   swift build -c release -Xswiftc -strict-concurrency=complete
   ```

4. **Package `agymg.app` locally**:
   ```bash
   ./Scripts/package_app.sh debug
   open ./agymg.app
   ```

5. **Run against an isolated sandbox Vault** (optional, useful for testing onboarding or destructive operations without touching your personal configs):
   ```bash
   mkdir -p /tmp/agymg-sandbox/.gemini /tmp/agymg-sandbox/Projects
   AGYMG_GEMINI_DIR=/tmp/agymg-sandbox/.gemini \
   AGYMG_PROJECTS_DIR=/tmp/agymg-sandbox/Projects \
   ./agymg.app/Contents/MacOS/agymg
   ```

## Pull Request Checklist

- [ ] `swift build -c release -Xswiftc -strict-concurrency=complete` succeeds with zero errors.
- [ ] `swift test` passes 100% of suites, including new unit tests for any added behavior.
- [ ] SwiftUI views perform zero disk I/O or JSON serialization inside `body`.
- [ ] All UI strings, CLI output, comments, and error messages are in English and contain no hardcoded machine paths.
- [ ] Read [`AGENTS.md`](AGENTS.md) for layout invariants (single outer `ScrollView` in `MasterVaultView` / `ProjectDetailView` and 4pt/8pt spacing grid).
