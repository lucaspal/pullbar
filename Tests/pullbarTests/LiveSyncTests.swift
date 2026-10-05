import AppKit
import XCTest
@testable import pullbar

@MainActor
final class LiveSyncTests: XCTestCase {
    private func inbox(directTitles: [String]) -> Inbox {
        let prs = directTitles.map { makePR(title: $0) }
        return Inbox.build(reviewRequested: prs, userReviewRequested: prs, authored: [], viewerLogin: "octocat")
    }

    private func menuText(_ app: AppDelegate) -> [String] {
        app.menuForTesting.items.map { $0.attributedTitle?.string ?? $0.title }
    }

    func testTheOpenMenuUpdatesAndTheTitleWaitsForClose() {
        let app = AppDelegate()
        app.installStatusItemForTesting()
        defer { app.removeStatusItemForTesting() }

        app.inboxForTesting = inbox(directTitles: ["First"])
        app.renderForTesting()
        XCTAssertEqual(app.statusTitleForTesting, "1")

        app.menuWillOpen(app.menuForTesting)
        XCTAssertTrue(app.menuIsOpenForTesting)
        app.rebuildMenuForTesting()

        // New data arrives while the menu is open.
        app.inboxForTesting = inbox(directTitles: ["First", "Second"])
        app.renderForTesting()
        XCTAssertTrue(menuText(app).contains { $0.hasPrefix("Second\n") }, "the open menu shows the new pull request")
        XCTAssertEqual(app.statusTitleForTesting, "1", "the menu bar title waits while the menu is open")
        XCTAssertTrue(app.statusTitleIsStaleForTesting)

        app.menuDidClose(app.menuForTesting)
        XCTAssertFalse(app.menuIsOpenForTesting)
        XCTAssertFalse(app.statusTitleIsStaleForTesting)
        XCTAssertEqual(app.statusTitleForTesting, "2", "the title is applied when the menu closes")
    }

    func testClosingWithoutChangesLeavesTheTitleAlone() {
        let app = AppDelegate()
        app.installStatusItemForTesting()
        defer { app.removeStatusItemForTesting() }

        app.inboxForTesting = inbox(directTitles: ["Only"])
        app.renderForTesting()
        app.menuWillOpen(app.menuForTesting)
        app.menuDidClose(app.menuForTesting)
        XCTAssertFalse(app.statusTitleIsStaleForTesting)
        XCTAssertEqual(app.statusTitleForTesting, "1")
    }
}

@MainActor
final class RefreshTimerTests: XCTestCase {
    private var savedInterval: TimeInterval = 120

    override func setUp() {
        super.setUp()
        savedInterval = Settings.shared.refreshInterval
    }

    override func tearDown() {
        Settings.shared.refreshInterval = savedInterval
        super.tearDown()
    }

    /// An open menu runs the event-tracking run-loop mode. A timer in the
    /// default mode only would not fire there, so refreshes would pause
    /// while you look at the menu.
    func testTheRefreshTimerFiresWhileTheMenuIsOpen() throws {
        // AppKit adds event tracking to the common modes, as in the real app.
        _ = NSApplication.shared
        let app = AppDelegate()
        Settings.shared.refreshInterval = 0.05
        app.scheduleTimerForTesting()
        let timer = try XCTUnwrap(app.timerForTesting)
        defer { timer.invalidate() }
        timer.tolerance = 0
        let firstFire = timer.fireDate

        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            RunLoop.current.run(mode: .eventTracking, before: deadline)
        }
        XCTAssertGreaterThan(timer.fireDate, firstFire, "the timer fired during event tracking")
    }

    func testLowBudgetStretchesTheAutomaticTimerToFifteenMinutes() throws {
        let app = AppDelegate()
        app.inboxForTesting = Inbox.build(
            reviewRequested: [], userReviewRequested: [], authored: [], viewerLogin: "octocat",
            apiUsage: APIUsage(
                limit: 5000, remaining: 499, resetAt: Date().addingTimeInterval(3600),
                lastRefreshCost: 2, lastRefreshRequests: 1
            )
        )
        app.scheduleTimerForTesting()
        let timer = try XCTUnwrap(app.timerForTesting)
        defer { timer.invalidate() }
        XCTAssertGreaterThanOrEqual(timer.fireDate.timeIntervalSinceNow, 899)
    }

    func testRateLimitTimerWaitsUntilAfterTheReset() throws {
        let app = AppDelegate()
        app.rateLimitBlockedUntilForTesting = Date().addingTimeInterval(120)
        app.scheduleTimerForTesting()
        let timer = try XCTUnwrap(app.timerForTesting)
        defer { timer.invalidate() }
        XCTAssertGreaterThanOrEqual(timer.fireDate.timeIntervalSinceNow, 120)
    }
}
