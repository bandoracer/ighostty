import XCTest
@testable import iGhostty

final class GhosttyParityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FileManager.default.changeCurrentDirectoryPath(Self.packageRoot.path)
    }

    func testConfigOverrideParserPreservesRepeatedKeysAndReportsInvalidLines() {
        let parsed = GhosttyConfigOverrides.parse("""
        # comment
        keybind = cmd+t=new_tab
        keybind = cmd+w=close_surface
        font-size = 14
        missing separator
         = value
        cursor-style =
        """)

        XCTAssertEqual(parsed.entries.map(\.key), ["keybind", "keybind", "font-size"])
        XCTAssertEqual(parsed.entries.map(\.value), ["cmd+t=new_tab", "cmd+w=close_surface", "14"])
        XCTAssertEqual(parsed.issues.map(\.line), [5, 6, 7])
    }

    func testGhosttyResourcesValidateFromSourceTree() {
        XCTAssertNil(GhosttyResources.validationIssue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: GhosttyResources.resourcesDir?.path ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: GhosttyResources.terminfoSourceURL?.path ?? ""))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: GhosttyResources.binDir?.appendingPathComponent("ghostty").path ?? ""))
    }

    func testShellIntegrationEnvironmentDefaultsToGhostty() {
        var profile = Profile()
        profile.termVariable = ""
        profile.shellIntegration = .none

        var env: [String: String] = [:]
        let launch = GhosttyShellIntegration.configure(
            shellPath: "/bin/zsh",
            args: [],
            loginShellName: "-zsh",
            profile: profile,
            environment: &env
        )

        XCTAssertEqual(launch.executable, "/bin/zsh")
        XCTAssertEqual(launch.execName, "-zsh")
        XCTAssertEqual(env["TERM"], "xterm-ghostty")
        XCTAssertEqual(env["COLORTERM"], "truecolor")
        XCTAssertEqual(env["TERM_PROGRAM"], "iGhostty")
        XCTAssertNotNil(env["GHOSTTY_RESOURCES_DIR"])
        XCTAssertNotNil(env["GHOSTTY_BIN_DIR"])
        XCTAssertNotNil(env["TERMINFO"])
    }

    func testShellIntegrationCursorFeatureFollowsProfileBlinkSetting() {
        XCTAssertEqual(
            GhosttyShellIntegration.effectiveFeatures("cursor:blink,path,title", cursorBlink: false),
            "cursor:steady,path,title"
        )
        XCTAssertEqual(
            GhosttyShellIntegration.effectiveFeatures("cursor:steady,path,title", cursorBlink: true),
            "cursor:blink,path,title"
        )
        XCTAssertEqual(
            GhosttyShellIntegration.canonicalFeatureText("cursor:blink,path,title"),
            "cursor,path,title"
        )
    }

    func testPromptMarksAreOptInAndFilteredFromGhosttyConfig() {
        XCTAssertFalse(GhosttyShellIntegration.promptMarksEnabled("cursor,path,title"))
        XCTAssertTrue(GhosttyShellIntegration.promptMarksEnabled("cursor,path,title,prompt"))
        XCTAssertEqual(
            GhosttyShellIntegration.ghosttyConfigFeatures("cursor,prompt,path,title", cursorBlink: false),
            "cursor:steady,path,title"
        )
    }

    func testShellIntegrationDisablesPromptMarksByDefault() {
        var profile = Profile()
        profile.shellIntegrationFeatures = "cursor,path,title"
        var env: [String: String] = [:]

        _ = GhosttyShellIntegration.configure(
            shellPath: "/bin/zsh",
            args: [],
            loginShellName: "-zsh",
            profile: profile,
            environment: &env
        )

        XCTAssertEqual(env["IGHOSTTY_DISABLE_PROMPT_MARKS"], "1")

        profile.shellIntegrationFeatures = "cursor,path,title,prompt"
        env = [:]
        _ = GhosttyShellIntegration.configure(
            shellPath: "/bin/zsh",
            args: [],
            loginShellName: "-zsh",
            profile: profile,
            environment: &env
        )
        XCTAssertNil(env["IGHOSTTY_DISABLE_PROMPT_MARKS"])
        XCTAssertEqual(env["GHOSTTY_SHELL_FEATURES"], "cursor:blink,path,title,prompt")
    }

    func testBundledShellIntegrationDoesNotClearActivePromptLine() throws {
        let shellIntegration = Self.packageRoot
            .appendingPathComponent("Support/GhosttyResources/share/ghostty/shell-integration", isDirectory: true)
        let zsh = try String(
            contentsOf: shellIntegration.appendingPathComponent("zsh/ghostty-integration"),
            encoding: .utf8
        )
        let bash = try String(
            contentsOf: shellIntegration.appendingPathComponent("bash/ghostty.bash"),
            encoding: .utf8
        )

        XCTAssertFalse(zsh.contains("133;A;cl=line"))
        XCTAssertFalse(bash.contains("133;A;redraw=last;cl=line"))
        XCTAssertTrue(zsh.contains("133;A"))
        XCTAssertTrue(bash.contains("133;A;aid="))
    }

    func testThemeCatalogAugmentsBuiltInSchemes() {
        let names = Set(
            ColorScheme.builtIns(for: .light).map(\.name) +
            ColorScheme.builtIns(for: .dark).map(\.name)
        )

        XCTAssertGreaterThan(names.count, 400)
        XCTAssertTrue(names.contains("Codex"))
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
