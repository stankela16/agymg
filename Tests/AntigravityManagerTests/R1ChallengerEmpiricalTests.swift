import XCTest
import SwiftUI
import AppKit
@testable import AntigravityManager

// Mock NSWindow to accurately simulate AppKit window states in headless test environments
final class MockControlCenterWindow: NSWindow {
    var mockIsMiniaturized: Bool = false
    var mockIsVisible: Bool = true
    var deminiaturizeCallCount: Int = 0
    var makeKeyAndOrderFrontCallCount: Int = 0
    var orderFrontRegardlessCallCount: Int = 0

    override var isMiniaturized: Bool { mockIsMiniaturized }
    override var isVisible: Bool { mockIsVisible }

    override func deminiaturize(_ sender: Any?) {
        super.deminiaturize(sender)
        deminiaturizeCallCount += 1
        mockIsMiniaturized = false
        mockIsVisible = true
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        makeKeyAndOrderFrontCallCount += 1
        mockIsVisible = true
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        orderFrontRegardlessCallCount += 1
        mockIsVisible = true
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        mockIsVisible = false
        mockIsMiniaturized = false
    }

    override func close() {
        super.close()
        mockIsVisible = false
        mockIsMiniaturized = false
    }
}

@MainActor
final class R1ChallengerEmpiricalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            WindowRouter.openControlCenter = nil
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            WindowRouter.openControlCenter = nil
        }
        super.tearDown()
    }

    private func createTestWindow(identifier: String?, title: String) -> MockControlCenterWindow {
        let window = MockControlCenterWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        if let identifier {
            window.identifier = NSUserInterfaceItemIdentifier(identifier)
        } else {
            window.identifier = nil
        }
        window.title = title
        window.mockIsVisible = true
        window.mockIsMiniaturized = false
        return window
    }

    // MARK: - Challenge 1: Window lookup for all 5 required titles with "control-center" identifier
    func testWindowLookupWithControlCenterIdentifier_AllTitles() {
        let titlesToTest = [
            "Master Vault",
            "Global Core",
            "acme-web",
            "agymg",
            "Settings"
        ]

        var results: [String: Bool] = [:]

        for title in titlesToTest {
            autoreleasepool {
                let window = createTestWindow(identifier: "control-center", title: title)
                let found = WindowRouter.findControlCenterWindow()
                results[title] = (found === window)
                window.orderOut(nil)
            }
        }

        print("Empirical Results (with identifier='control-center'): \(results)")

        // 1. Master Vault -> Expected: FOUND
        XCTAssertTrue(results["Master Vault"] == true, "Window with title 'Master Vault' must be found")

        // 2. Global Core -> Expected: FOUND
        XCTAssertTrue(results["Global Core"] == true, "Window with title 'Global Core' must be found")

        // 3. acme-web -> Expected: FOUND
        XCTAssertTrue(results["acme-web"] == true, "Window with title 'acme-web' must be found")

        // 4. agymg -> Expected: FOUND
        XCTAssertTrue(results["agymg"] == true, "Window with title 'agymg' must be found")

        // 5. Settings -> Expected: FOUND (with identifier 'control-center' prioritized over Settings title)
        let settingsFound = results["Settings"] == true
        print("[EMPIRICAL EVIDENCE] Settings title lookup with id 'control-center': \(settingsFound ? "PASSED" : "FAILED")")
        XCTAssertTrue(settingsFound, "WindowRouter must find window with identifier 'control-center' even when title is 'Settings'")
    }

    // MARK: - Challenge 1b: Window lookup for all 5 required titles WITHOUT identifier (fallback check)
    func testWindowLookupWithoutIdentifier_AllTitles() {
        let titlesToTest = [
            "Master Vault",
            "Global Core",
            "acme-web",
            "agymg",
            "Settings"
        ]

        var results: [String: Bool] = [:]

        for title in titlesToTest {
            autoreleasepool {
                let window = createTestWindow(identifier: nil, title: title)
                let found = WindowRouter.findControlCenterWindow()
                results[title] = (found === window)
                window.orderOut(nil)
            }
        }

        print("Empirical Results (without identifier): \(results)")
        // Expected without identifier:
        // "Master Vault": true (matches knownNavTitles)
        // "Global Core": true (matches knownNavTitles)
        // "agymg": true (matches window.title == "agymg")
        // "acme-web": false (not in knownNavTitles, lacks identifier)
        // "Settings": false (excluded by line 28)
        XCTAssertTrue(results["Master Vault"] == true, "Master Vault matches knownNavTitles")
        XCTAssertTrue(results["Global Core"] == true, "Global Core matches knownNavTitles")
        XCTAssertTrue(results["agymg"] == true, "agymg matches default title")
        XCTAssertFalse(results["acme-web"] == true, "Without identifier, arbitrary project names cannot match knownNavTitles")
        XCTAssertFalse(results["Settings"] == true, "Without identifier, Settings is excluded")
    }

    // MARK: - Challenge 2: Miniaturized, Obscured, and Hidden Windows
    func testWindowLookup_Miniaturized_Obscured_Hidden() {
        // 1. Miniaturized window in Dock (isVisible == false, isMiniaturized == true)
        let minWindow = createTestWindow(identifier: "control-center", title: "Master Vault")
        minWindow.mockIsVisible = false
        minWindow.mockIsMiniaturized = true

        let foundMin = WindowRouter.findControlCenterWindow()
        XCTAssertNotNil(foundMin, "Miniaturized window in Dock must be found by findControlCenterWindow()")
        XCTAssertTrue(foundMin === minWindow)

        // Test triggerOpen deminiaturizes it
        var fallbackCalled = false
        WindowRouter.openControlCenter = { fallbackCalled = true }
        WindowRouter.triggerOpen()

        XCTAssertTrue(minWindow.deminiaturizeCallCount > 0, "triggerOpen must call deminiaturize() on miniaturized window")
        XCTAssertTrue(minWindow.orderFrontRegardlessCallCount > 0, "triggerOpen must order front regardless")
        XCTAssertFalse(fallbackCalled, "Fallback openControlCenter must NOT be called when miniaturized window exists")
        minWindow.orderOut(nil)

        // 2. Obscured (visible but behind other windows)
        let obsWindow = createTestWindow(identifier: "control-center", title: "Global Core")
        obsWindow.mockIsVisible = true
        obsWindow.mockIsMiniaturized = false

        let foundObs = WindowRouter.findControlCenterWindow()
        XCTAssertNotNil(foundObs, "Obscured background window must be found")
        XCTAssertTrue(foundObs === obsWindow)

        fallbackCalled = false
        WindowRouter.triggerOpen()
        XCTAssertTrue(obsWindow.makeKeyAndOrderFrontCallCount > 0, "triggerOpen must bring obscured window to front")
        XCTAssertFalse(fallbackCalled, "Fallback must not be called")
        obsWindow.orderOut(nil)

        // 3. Hidden / Closed window (isVisible == false and isMiniaturized == false)
        let hiddenWindow = createTestWindow(identifier: "control-center", title: "agymg")
        hiddenWindow.mockIsVisible = false
        hiddenWindow.mockIsMiniaturized = false

        let foundHidden = WindowRouter.findControlCenterWindow()
        XCTAssertNil(foundHidden, "Closed/hidden window must NOT be found as active window")
        hiddenWindow.orderOut(nil)
    }

    // MARK: - Challenge 3: Exclusions (Settings, Popovers, Panels)
    func testExclusionsNeverMistakenForControlCenter() {
        // 1. Standalone SwiftUI Settings window
        let settingsWindow = MockControlCenterWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        settingsWindow.title = "Settings"
        settingsWindow.mockIsVisible = true

        // 2. Popover window with status bar level
        let popoverWindow = MockControlCenterWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        popoverWindow.level = .statusBar
        popoverWindow.title = "agymg MenuBar Popover"
        popoverWindow.mockIsVisible = true

        // 3. NSOpenPanel
        let openPanel = NSOpenPanel()
        openPanel.title = "agymg Open Project"
        openPanel.setIsVisible(true)

        // 4. NSSavePanel
        let savePanel = NSSavePanel()
        savePanel.title = "agymg Export Config"
        savePanel.setIsVisible(true)

        // Verify none of these 4 windows are ever identified as Control Center
        let found = WindowRouter.findControlCenterWindow()
        XCTAssertNil(
            found,
            "Settings window, Popovers, NSOpenPanel, and NSSavePanel must NEVER be mistaken for Control Center"
        )

        settingsWindow.orderOut(nil)
        popoverWindow.orderOut(nil)
        openPanel.orderOut(nil)
        savePanel.orderOut(nil)
    }

    // MARK: - Challenge 4: triggerOpen() Behavior across all 3 states
    func testTriggerOpen_NoWindow_AlreadyKey_MinimizedInDock() {
        // Case A: No window exists -> fallback openControlCenter is invoked
        var fallbackCalled = false
        WindowRouter.openControlCenter = {
            fallbackCalled = true
        }
        WindowRouter.triggerOpen()
        XCTAssertTrue(fallbackCalled, "When no window exists, fallback openControlCenter must be called")

        // Case B: Window already exists and is key -> fallback is NOT called, window remains front
        fallbackCalled = false
        let keyWindow = createTestWindow(identifier: "control-center", title: "Master Vault")
        keyWindow.mockIsVisible = true

        WindowRouter.triggerOpen()
        XCTAssertFalse(fallbackCalled, "When window is already key, fallback must NOT be called")
        XCTAssertTrue(keyWindow.makeKeyAndOrderFrontCallCount > 0)
        keyWindow.orderOut(nil)

        // Case C: Window is minimized in Dock -> deminiaturized, made key, fallback NOT called
        fallbackCalled = false
        let minWindow = createTestWindow(identifier: "control-center", title: "Global Core")
        minWindow.mockIsVisible = false
        minWindow.mockIsMiniaturized = true

        WindowRouter.triggerOpen()
        XCTAssertFalse(fallbackCalled, "When window is miniaturized, fallback must NOT be called")
        XCTAssertTrue(minWindow.deminiaturizeCallCount > 0, "deminiaturize must be called")
        XCTAssertTrue(minWindow.orderFrontRegardlessCallCount > 0, "orderFrontRegardless must be called")
        minWindow.orderOut(nil)
    }

    // MARK: - Challenge 5: Settings Tab Navigation Bug in ControlCenterView
    func testSettingsTabNavigationBugEmpiricalProof() {
        // When ControlCenterView has navigationSelection = .settings, its navigationTitle is "Settings"
        // and its identifier is "control-center".
        let controlCenterInSettingsTab = createTestWindow(identifier: "control-center", title: "Settings")
        controlCenterInSettingsTab.mockIsVisible = true

        let found = WindowRouter.findControlCenterWindow()
        
        var fallbackCalled = false
        WindowRouter.openControlCenter = { fallbackCalled = true }
        WindowRouter.triggerOpen()

        // EMPIRICAL VERIFICATION:
        // WindowRouter prioritizes window scene identifier "control-center",
        // correctly finding the window and deminiaturizing/focusing without fallback!
        print("[EMPIRICAL VERIFICATION] findControlCenterWindow when title='Settings' returned: \(String(describing: found))")
        print("[EMPIRICAL VERIFICATION] Fallback openControlCenter called: \(fallbackCalled)")

        XCTAssertNotNil(
            found,
            "FIX VERIFIED: WindowRouter correctly finds the Control Center window when in the Settings tab"
        )
        XCTAssertFalse(
            fallbackCalled,
            "FIX VERIFIED: triggerOpen deminiaturizes and brings existing Settings-tab window to front without fallback"
        )

        controlCenterInSettingsTab.orderOut(nil)
    }
}
