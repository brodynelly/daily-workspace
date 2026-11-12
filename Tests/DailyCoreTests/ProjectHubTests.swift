import XCTest

@testable import DailyCore

final class ProjectHubParsingTests: XCTestCase {
    private let hub = """
        ---
        type: project
        tags:
          - project
          - daily-workspace
        title: "Frontmatter title"
        ---

        # Daily Workspace

        ## Purpose and Workspace Boundary

        This hub connects the application to its repository
        and to relevant vault knowledge.

        - a list item is not purpose prose

        The vault is the readable context layer.

        ## Repository

        [Open the checkout](file:///Users/me/github/misc/daily-workspace/)

        Local path: `/Users/me/github/misc/daily-workspace/`.

        - **Local path:** `/Users/me/github/other%20repo`
        - Bare link file:///Users/me/github/third and [docs](file:///Users/me/docs%20folder/)

        ```sh
        cd file:///Users/me/in-code
        ```

        ## Decisions and Unknowns

        - Keep the application checkout in place.
        - Confirm the intended vault path, capture destination and task ownership
          before changing application integration.
        - [ ] a historical checkbox stays text

        ## Context
        """

    func testHubFields() {
        let parsed = ProjectHubParser.hub(text: hub, path: "01-projects/daily-workspace/daily-workspace.md")
        XCTAssertEqual(parsed.slug, "daily-workspace")
        XCTAssertEqual(parsed.projectKey, "daily-workspace")
        XCTAssertEqual(parsed.title, "Daily Workspace")
        XCTAssertEqual(parsed.tags, ["project", "daily-workspace"])
        XCTAssertEqual(parsed.folder, "01-projects/daily-workspace")
        XCTAssertEqual(
            parsed.purpose,
            "This hub connects the application to its repository and to relevant vault knowledge.\n\n"
                + "The vault is the readable context layer.")
        XCTAssertEqual(
            parsed.repositories.map(\.path),
            [
                "/Users/me/github/misc/daily-workspace", "/Users/me/github/other%20repo", "/Users/me/github/third",
                "/Users/me/docs folder",
            ])
        XCTAssertEqual(parsed.repositories.first?.label, "Open the checkout")
        XCTAssertEqual(parsed.repositories.first?.source, .fileLink)
        XCTAssertEqual(parsed.repositories[1].source, .localPath)
        XCTAssertEqual(
            parsed.decisions,
            [
                "Keep the application checkout in place.",
                "Confirm the intended vault path, capture destination and task ownership before changing application integration.",
                "[ ] a historical checkbox stays text",
            ])
    }

    func testPurposeIsBoundedAndFallsBackToPreamble() {
        let long = "# T\n\nIntro words " + String(repeating: "word ", count: 200) + "\n\n## Next\n\nOther."
        let parsed = ProjectHubParser.hub(text: long, path: "01-projects/t.md", maxPurposeLength: 40)
        XCTAssertEqual(parsed.purpose, "Intro words word word word word word…")
        XCTAssertEqual(ProjectHubParser.hub(text: "no heading", path: "01-projects/x.md").title, "x")
        let keyed = ProjectHubParser.hub(
            text: "---\ntype: project\nproject: brain\n---\n# B", path: "01-projects/b/b-project.md")
        XCTAssertEqual(keyed.slug, "b-project")
        XCTAssertEqual(keyed.projectKey, "brain")
    }

    func testFrontmatterVariants() throws {
        let inline = try XCTUnwrap(Frontmatter.split(markdown: "---\n\ntype: 'project'\ntags: [a, \"b c\"]\n---\n# H"))
        XCTAssertEqual(inline.frontmatter.scalars["type"], "project")
        XCTAssertEqual(inline.frontmatter.tags, ["a", "b c"])
        XCTAssertEqual(inline.bodyStart, 5)
        XCTAssertNil(Frontmatter.split(markdown: "# No frontmatter\ntype: project"))
        XCTAssertNil(Frontmatter.split(markdown: "---\ntype: project\nnever closed"))
    }

    func testProjectStateFields() {
        let text = """
            ---
            type: project-state
            ---
            # Project State

            ## Definition of done

            The app reads Org.

            ## Current reality

            Readers exist.

            ## Next executable action

            Wire the Open Loops screen.

            ## Exact restart

            - **File:** Sources/DailyCore/Loops/OrgReader.swift
            - **Symbol / line:**
            - **Command:** swift test

            ## Blockers

            -

            ## Decisions made

            - Read-only first.
            """
        let state = ProjectHubParser.state(text: text, path: "01-projects/p/notes/state.md")
        XCTAssertEqual(state.definitionOfDone, "The app reads Org.")
        XCTAssertEqual(state.currentState, "Readers exist.")
        XCTAssertEqual(state.nextAction, "Wire the Open Loops screen.")
        XCTAssertEqual(state.restart.map(\.key), ["File", "Command"])
        XCTAssertEqual(state.restart.last?.value, "swift test")
        XCTAssertEqual(state.blockers, [])
        XCTAssertEqual(state.decisions, ["Read-only first."])

        let inline = ProjectHubParser.state(
            text: "- **Current state:** green\n**Next exact action:** ship", path: "s.md")
        XCTAssertEqual(inline.currentState, "green")
        XCTAssertEqual(inline.nextAction, "ship")
    }

    func testStateNoteDetection() {
        var template = Frontmatter()
        template.scalars["type"] = "template"
        template.lists["tags"] = ["project-state"]
        XCTAssertFalse(ProjectHubParser.isStateNote(path: "x/project-state.md", frontmatter: template))
        var tagged = Frontmatter()
        tagged.lists["tags"] = ["project-state"]
        XCTAssertTrue(ProjectHubParser.isStateNote(path: "x/anything.md", frontmatter: tagged))
        XCTAssertTrue(ProjectHubParser.isStateNote(path: "x/app-current-state.md", frontmatter: Frontmatter()))
        XCTAssertFalse(ProjectHubParser.isStateNote(path: "x/notes.md", frontmatter: Frontmatter()))
    }
}

final class ProjectHubReaderTests: XCTestCase {
    private func hubText(_ title: String) -> String { "---\ntype: project\n---\n# \(title)\n\nPurpose of \(title).\n" }

    func testMissingAndEmptyProjectsFolder() throws {
        let vault = try FixtureVault()
        XCTAssertEqual(
            ProjectHubReader(root: vault.root).read(now: fixtureNow).state,
            .unavailable(reason: "01-projects was not found"))
        try vault.write("01-projects/readme.md", "---\ntype: guide\n---\n# Not a hub")
        XCTAssertEqual(ProjectHubReader(root: vault.root).read(now: fixtureNow).state, .empty)
    }

    func testDiscoveryDepthAndExclusions() throws {
        let vault = try FixtureVault()
        try vault.write("01-projects/top.md", hubText("Top"))
        try vault.write("01-projects/luuna/luuna.md", hubText("Luuna"))
        try vault.write("01-projects/personal/dotfiles/dotfiles.md", hubText("Dotfiles"))
        try vault.write("01-projects/work/kotc/pulse/pulse-project.md", hubText("Too deep"))
        try vault.write("01-projects/work/ingest-kanban.md", hubText("Board"))
        try vault.write("01-projects/work/x-board.md", hubText("Board"))
        try vault.write("01-projects/_drafts/draft.md", hubText("Draft"))
        try vault.write("01-projects/.hidden/h.md", hubText("Hidden"))
        try vault.write("01-projects/repo/.git/HEAD", "ref: main")
        try vault.write("01-projects/repo/repo.md", hubText("Nested repo"))
        try vault.write("01-projects/luuna/notes.md", "---\ntype: guide\n---\n# Guide")
        let observation = ProjectHubReader(root: vault.root).read(now: fixtureNow)
        XCTAssertEqual(observation.state, .populated)
        XCTAssertEqual(observation.value.map(\.slug), ["luuna", "dotfiles", "top"])
        XCTAssertEqual(
            ProjectHubReader(root: vault.root, maxDepth: 4).read(now: fixtureNow).value.map(\.slug),
            ["luuna", "dotfiles", "top", "pulse-project"])
    }

    func testNotesFolderListingAndStateNote() throws {
        let vault = try FixtureVault()
        try vault.write("01-projects/app/app.md", hubText("App"))
        try vault.write("01-projects/app/notes/older.md", "# Older")
        try vault.write("01-projects/app/notes/newer.md", "# Newer")
        try vault.write("01-projects/app/notes/old-kanban.md", "# Board")
        try vault.write(
            "01-projects/app/notes/project-state.md", "# State\n\n## Next exact action\n\nRun the probe.\n")
        try vault.setModified("01-projects/app/notes/older.md", Date(timeIntervalSince1970: 1_000))
        try vault.setModified("01-projects/app/notes/newer.md", Date(timeIntervalSince1970: 3_000))
        try vault.setModified("01-projects/app/notes/project-state.md", Date(timeIntervalSince1970: 2_000))
        let hub = try XCTUnwrap(ProjectHubReader(root: vault.root).read(now: fixtureNow).value.first)
        XCTAssertEqual(hub.purpose, "Purpose of App.")
        XCTAssertEqual(hub.notes.map(\.title), ["newer", "project-state", "older"])
        XCTAssertEqual(hub.latestNoteModified, Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(hub.state?.path, "01-projects/app/notes/project-state.md")
        XCTAssertEqual(hub.state?.nextAction, "Run the probe.")
    }

    func testMarkdownCheckboxesNeverBecomeLoops() throws {
        let vault = try FixtureVault()
        try vault.write("org/inbox.org", "* Tasks\n- [ ] org checkbox\n")
        try vault.write("org/projects.org", "* Projects\n")
        try vault.write("01-projects/p/p.md", "---\ntype: project\n---\n# P\n\n- [ ] historical\n- [x] done\n")
        XCTAssertEqual(OrgReader(root: vault.root).readLoops(now: fixtureNow).state, .empty)
        let hub = ProjectHubReader(root: vault.root).read(now: fixtureNow).value.first
        XCTAssertEqual(hub?.decisions, [])
        XCTAssertNil(hub?.purpose)
    }
}
