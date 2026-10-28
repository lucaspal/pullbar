import AppKit
import XCTest
@testable import pullbar

@MainActor
final class StatusTextTests: XCTestCase {
    private func inbox(direct: Int = 0, teams: Int = 0, action: Int = 0) -> Inbox {
        let directPRs = (0..<direct).map { makePR(id: "d\($0)") }
        let teamPRs = (0..<teams).map { makePR(id: "t\($0)") }
        let actionPRs = (0..<action).map { makePR(id: "a\($0)", reviewDecision: .changesRequested) }
        return Inbox.build(
            reviewRequested: directPRs + teamPRs,
            userReviewRequested: directPRs,
            authored: actionPRs,
            viewerLogin: "octocat",
            now: referenceDate
        )
    }

    private func title(_ inbox: Inbox?, error: Error? = nil) -> String? {
        AppDelegate.statusText(inbox: inbox, error: error)?.title
    }

    func testTitleCombinations() {
        XCTAssertEqual(title(inbox()), "")
        XCTAssertEqual(title(inbox(direct: 3)), "3")
        XCTAssertEqual(title(inbox(direct: 3, teams: 2)), "3+2")
        XCTAssertEqual(title(inbox(teams: 2)), "0+2")
        XCTAssertEqual(title(inbox(action: 1)), "⚠︎1")
        XCTAssertEqual(title(inbox(direct: 3, teams: 2, action: 1)), "3+2 ⚠︎1")
    }

    func testFailedRefreshAddsAnExclamationMark() {
        XCTAssertEqual(title(inbox(direct: 3), error: GitHubError.malformed), "3 !")
        XCTAssertEqual(title(inbox(), error: GitHubError.malformed), "!")
    }

    func testToolTipListsEverySection() throws {
        let toolTip = try XCTUnwrap(AppDelegate.statusText(inbox: inbox(direct: 1, teams: 2), error: nil)?.toolTip)
        XCTAssertEqual(toolTip.split(separator: "\n").count, InboxSection.allCases.count)
        XCTAssertTrue(toolTip.hasPrefix("Needs your review: 1\nNeeds your teams' review: 2\n"))
    }

    func testErrorWithoutDataShowsTheError() {
        let text = AppDelegate.statusText(inbox: nil, error: GitHubError.unauthorized)
        XCTAssertEqual(text?.title, "!")
        XCTAssertEqual(text?.toolTip, GitHubError.unauthorized.errorDescription)
    }

    func testNothingYetLeavesTheTitleAlone() {
        XCTAssertNil(AppDelegate.statusText(inbox: nil, error: nil))
    }
}

@MainActor
final class AppDelegateHelperTests: XCTestCase {
    func testIntervalLabel() {
        let app = AppDelegate()
        XCTAssertEqual(app.intervalLabelForTesting(60), "1 minute")
        XCTAssertEqual(app.intervalLabelForTesting(90), "1 minute")
        XCTAssertEqual(app.intervalLabelForTesting(120), "2 minutes")
        XCTAssertEqual(app.intervalLabelForTesting(300), "5 minutes")
        XCTAssertEqual(app.intervalLabelForTesting(900), "15 minutes")
    }

    func testTruncate() {
        let app = AppDelegate()
        XCTAssertEqual(app.truncateForTesting("short", to: 10), "short")
        XCTAssertEqual(app.truncateForTesting("exactly10!", to: 10), "exactly10!")
        XCTAssertEqual(app.truncateForTesting("eleven chars", to: 10), "eleven ch…")
        XCTAssertEqual(app.truncateForTesting("eleven chars", to: 10).count, 10)
    }
}

@MainActor
final class MenuTests: XCTestCase {
    private func menuTitles(_ app: AppDelegate) -> [String] {
        app.menuForTesting.items.map { $0.isSeparatorItem ? "---" : ($0.attributedTitle?.string ?? $0.title) }
    }

    func testLoadingMenu() {
        let app = AppDelegate()
        app.rebuildMenuForTesting()
        let titles = menuTitles(app)

        // Headers have no count while loading, and the sections come in order.
        let headers = titles.filter { $0 == $0.uppercased() && $0 != "---" && !$0.isEmpty }
        XCTAssertEqual(headers, InboxSection.allCases.map { $0.title.uppercased() })
        XCTAssertEqual(titles.filter { $0 == "Loading…" }.count, InboxSection.allCases.count)
        XCTAssertFalse(titles.contains { $0.hasPrefix("Could not load the inbox") })
        XCTAssertEqual(app.menuForTesting.items.last?.title, "Quit pullbar")
        XCTAssertEqual(app.menuForTesting.items.last?.keyEquivalent, "q")
    }

    func testErrorMenu() throws {
        let app = AppDelegate()
        app.lastErrorForTesting = GitHubError.unauthorized
        app.rebuildMenuForTesting()
        let titles = menuTitles(app)

        // The error block comes before the first section.
        let error = try XCTUnwrap(titles.firstIndex(of: "Could not load the inbox\nGitHub rejected the token (401). Set a new one."))
        let firstSection = try XCTUnwrap(titles.firstIndex(of: "NEEDS YOUR REVIEW"))
        XCTAssertLessThan(error, firstSection)
        XCTAssertFalse(app.menuForTesting.items[error].isEnabled)
        XCTAssertEqual(titles[error + 1], "Set GitHub token…")
        XCTAssertEqual(titles[error + 2], "---")
    }

    func testInboxMenu() throws {
        let pr = makePR(
            number: 42, title: "Fix the thing", updatedAt: Date().addingTimeInterval(-3600),
            author: "mona", repository: "acme/api", reviewDecision: .approved,
            mergeable: .conflicting, checks: checks(.success, passed: 3, total: 4), commentCount: 5
        )
        let app = AppDelegate()
        app.inboxForTesting = Inbox.build(reviewRequested: [pr], userReviewRequested: [pr], authored: [], viewerLogin: "octocat")
        app.rebuildMenuForTesting()
        let titles = menuTitles(app)

        // The first section runs from its header to the next separator. The
        // pull request row is found by the URL it opens, so rows that other
        // features add inside a section (such as subheadings) don't matter.
        let s = try XCTUnwrap(titles.firstIndex(of: "NEEDS YOUR REVIEW  1"))
        let end = try XCTUnwrap(titles[s...].firstIndex(of: "---"), "the section ends with a separator")
        let row = try XCTUnwrap(app.menuForTesting.items[s..<end].firstIndex { $0.representedObject as? URL == pr.url })
        XCTAssertTrue(titles[row].hasPrefix("Fix the thing\nacme/api#42 · mona · updated "), titles[row])
        for part in ["Approved", "3/4", "conflicts", "💬 5"] {
            XCTAssertTrue(titles[row].contains(part), "\(part) missing from \(titles[row])")
        }
        XCTAssertEqual(titles[end + 1], "NEEDS YOUR TEAMS' REVIEW  0")
        XCTAssertEqual(titles[end + 2], "Nothing to review")

        let item = app.menuForTesting.items[row]
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.toolTip, "acme/api#42\nFix the thing\n\nClick to open on GitHub")
        XCTAssertGreaterThanOrEqual(item.indentationLevel, 1, "rows sit under their section header")

        for (section, empty) in zip(InboxSection.allCases.dropFirst(), ["Nothing to review", "No drafts", "All caught up", "Nothing needs your action", "Nothing ready to merge", "Nothing queued"]) {
            XCTAssertTrue(titles.contains(empty), "\(section) should say \(empty)")
        }
        let refresh = try XCTUnwrap(titles.first { $0.hasPrefix("Refresh now") })
        XCTAssertTrue(refresh.contains("Updated ") && refresh.hasSuffix(" · signed in as octocat"), refresh)
    }

    func testLongTitlesAreTruncated() {
        let long = String(repeating: "a", count: 200)
        let app = AppDelegate()
        let pr = makePR(title: long)
        app.inboxForTesting = Inbox.build(reviewRequested: [], userReviewRequested: [], authored: [pr], viewerLogin: "")
        app.rebuildMenuForTesting()
        let row = app.menuForTesting.items.first { $0.representedObject as? URL == pr.url }
        XCTAssertEqual(row?.attributedTitle?.string.components(separatedBy: "\n").first?.count, 96)
    }

    func testSettingsAndActions() {
        let app = AppDelegate()
        app.rebuildMenuForTesting()
        let titles = menuTitles(app)
        for expected in ["Open inbox on GitHub", "Set GitHub token…", "Launch at login", "Check for updates…", "Quit pullbar"] {
            XCTAssertTrue(titles.contains(expected), "missing \(expected)")
        }
        XCTAssertEqual(app.menuForTesting.items.first { $0.title == "Open inbox on GitHub" }?.keyEquivalent, "o")

        let updated = app.menuForTesting.items.first { $0.title.hasPrefix("Updated: ") }
        XCTAssertEqual(updated?.submenu?.items.map(\.title), UpdatedWindow.allCases.map(\.title))
        XCTAssertEqual(updated?.submenu?.items.filter { $0.state == .on }.count, 1)

        let interval = app.menuForTesting.items.first { $0.title.hasPrefix("Refresh every: ") }
        XCTAssertEqual(interval?.submenu?.items.map(\.title), ["1 minute", "2 minutes", "5 minutes", "15 minutes"])
        XCTAssertEqual(interval?.submenu?.items.filter { $0.state == .on }.count, 1)
    }
}

@MainActor
final class MenuActionTests: XCTestCase {
    private var savedWindow: UpdatedWindow = .month
    private var savedInterval: TimeInterval = 120

    override func setUp() {
        super.setUp()
        savedWindow = Settings.shared.updatedWindow
        savedInterval = Settings.shared.refreshInterval
    }

    override func tearDown() {
        Settings.shared.updatedWindow = savedWindow
        Settings.shared.refreshInterval = savedInterval
        super.tearDown()
    }

    private func submenuItem(_ app: AppDelegate, parent prefix: String, title: String) throws -> NSMenuItem {
        let parent = try XCTUnwrap(app.menuForTesting.items.first { $0.title.hasPrefix(prefix) })
        return try XCTUnwrap(parent.submenu?.items.first { $0.title == title })
    }

    func testMenuDelegateBuildsTheMenu() {
        let app = AppDelegate()
        app.menuNeedsUpdate(app.menuForTesting)
        XCTAssertFalse(app.menuForTesting.items.isEmpty)
        // Opening and closing without a token must not start anything or crash.
        app.menuWillOpen(app.menuForTesting)
        app.menuDidClose(app.menuForTesting)
    }

    func testChoosingAnUpdatedWindowSavesIt() throws {
        let app = AppDelegate()
        Settings.shared.updatedWindow = .month
        app.rebuildMenuForTesting()
        let item = try submenuItem(app, parent: "Updated: ", title: "Last week")
        XCTAssertEqual(item.state, .off)
        _ = app.perform(try XCTUnwrap(item.action), with: item)
        XCTAssertEqual(Settings.shared.updatedWindow, .week)

        app.rebuildMenuForTesting()
        XCTAssertEqual(try submenuItem(app, parent: "Updated: ", title: "Last week").state, .on)
        XCTAssertEqual(app.menuForTesting.items.first { $0.title.hasPrefix("Updated: ") }?.title, "Updated: Last week")
    }

    func testChoosingARefreshIntervalSavesIt() throws {
        let app = AppDelegate()
        Settings.shared.refreshInterval = 120
        app.rebuildMenuForTesting()
        let item = try submenuItem(app, parent: "Refresh every: ", title: "5 minutes")
        _ = app.perform(try XCTUnwrap(item.action), with: item)
        XCTAssertEqual(Settings.shared.refreshInterval, 300)

        app.rebuildMenuForTesting()
        XCTAssertEqual(app.menuForTesting.items.first { $0.title.hasPrefix("Refresh every: ") }?.title, "Refresh every: 5 minutes")
    }
}
