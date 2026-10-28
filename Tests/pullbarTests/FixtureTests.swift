import AppKit
import XCTest
@testable import pullbar

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

final class FixtureTests: XCTestCase {
    private func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRelativeTimes() {
        XCTAssertEqual(Fixture.PR.seconds("45m"), 2700)
        XCTAssertEqual(Fixture.PR.seconds("3h"), 10_800)
        XCTAssertEqual(Fixture.PR.seconds("2d"), 172_800)
        XCTAssertEqual(Fixture.PR.seconds("5w"), 3_024_000)
        XCTAssertEqual(Fixture.PR.seconds("1.5h"), 5400)
        for bad in ["3y", "", "h", "tenm", "3 h"] {
            XCTAssertNil(Fixture.PR.seconds(bad), bad)
        }
    }

    func testFixtureArgument() {
        XCTAssertEqual(Fixture.path(in: ["pullbar", "--fixture", "/tmp/x.json"]), "/tmp/x.json")
        XCTAssertNil(Fixture.path(in: ["pullbar"]))
        XCTAssertNil(Fixture.path(in: ["pullbar", "--fixture"]), "flag without a value")
    }

    func testFixtureBecomesAnInbox() throws {
        let url = try write("""
        {
          "viewerLogin": "octocat",
          "direct": [{ "number": 1, "title": "Direct", "repository": "acme/a", "author": "mona", "updated": "1h" }],
          "teams": [{ "number": 2, "title": "Team", "repository": "acme/b", "author": "hubot", "updated": "2h" }],
          "authored": [
            { "number": 3, "title": "Draft", "repository": "acme/c", "author": "octocat", "updated": "3h", "isDraft": true },
            { "number": 4, "title": "Ready", "repository": "acme/c", "author": "octocat", "updated": "4h",
              "reviewDecision": "APPROVED", "checks": { "state": "SUCCESS", "passed": 5, "total": 5 }, "comments": 12 },
            { "number": 5, "title": "Conflict", "repository": "acme/c", "author": "octocat", "updated": "1d",
              "reviewDecision": "APPROVED", "mergeable": "CONFLICTING" }
          ]
        }
        """)
        let inbox = try Fixture.load(from: url).inbox(now: referenceDate)
        XCTAssertEqual(inbox.viewerLogin, "octocat")
        XCTAssertEqual(inbox.pullRequests(in: .needsYourReview).map(\.title), ["Direct"])
        XCTAssertEqual(inbox.pullRequests(in: .needsTeamsReview).map(\.title), ["Team"])
        XCTAssertEqual(inbox.pullRequests(in: .yourDrafts).map(\.title), ["Draft"])
        XCTAssertEqual(inbox.pullRequests(in: .readyToMerge).map(\.title), ["Ready"])
        XCTAssertEqual(inbox.pullRequests(in: .needsAction).map(\.title), ["Conflict"])

        let direct = try XCTUnwrap(inbox.pullRequests(in: .needsYourReview).first)
        XCTAssertEqual(direct.id, "acme/a#1")
        XCTAssertEqual(direct.url.absoluteString, "https://github.com/acme/a/pull/1")
        XCTAssertEqual(direct.updatedAt, referenceDate.addingTimeInterval(-3600))
        XCTAssertFalse(direct.isDraft)
        XCTAssertEqual(direct.mergeable, .mergeable)
        XCTAssertNil(direct.checks)
        XCTAssertEqual(direct.commentCount, 0)

        let ready = try XCTUnwrap(inbox.pullRequests(in: .readyToMerge).first)
        XCTAssertEqual(ready.checks, Checks(state: .success, total: 5, passed: 5))
        XCTAssertEqual(ready.commentCount, 12)
    }

    @MainActor
    func testQueuedFixtureAppearsInMenuAndTooltip() throws {
        let url = try write("""
        { "viewerLogin": "octocat", "authored": [
          { "number": 8, "title": "Waiting in merge queue", "repository": "acme/api",
            "author": "octocat", "updated": "1h", "isInMergeQueue": true }
        ] }
        """)
        let app = AppDelegate()
        app.inboxForTesting = try Fixture.load(from: url).inbox(now: referenceDate)
        app.rebuildMenuForTesting()
        let titles = app.menuForTesting.items.map { $0.attributedTitle?.string ?? $0.title }
        let ready = try XCTUnwrap(titles.firstIndex(of: "READY TO MERGE  0"))
        let queued = try XCTUnwrap(titles.firstIndex(of: "QUEUED  1"))
        XCTAssertGreaterThan(queued, ready)
        let row = try XCTUnwrap(app.menuForTesting.items.first { $0.representedObject as? URL == URL(string: "https://github.com/acme/api/pull/8") })
        XCTAssertTrue(row.attributedTitle?.string.contains("● Queued") == true)
        XCTAssertTrue(AppDelegate.statusText(inbox: app.inboxForTesting, error: nil)?.toolTip?.contains("Queued: 1") == true)
    }

    func testInvalidValuesNameThePullRequestAndField() throws {
        let cases = [
            (#""updated": "3y""#, "updated must look like"),
            (#""updated": "1h", "reviewDecision": "MAYBE""#, "unknown reviewDecision MAYBE"),
            (#""updated": "1h", "mergeable": "SOMETIMES""#, "unknown mergeable SOMETIMES"),
            (#""updated": "1h", "checks": { "state": "GREEN", "passed": 1, "total": 1 }"#, "unknown checks state GREEN"),
        ]
        for (fields, message) in cases {
            let url = try write(#"{ "viewerLogin": "x", "authored": [{ "number": 1, "title": "t", "repository": "acme/app", "author": "a", "# + fields + " }] }")
            XCTAssertThrowsError(try Fixture.load(from: url).inbox(now: referenceDate)) { error in
                let text = error.localizedDescription
                XCTAssertTrue(text.hasPrefix("Fixture acme/app#1: "), text)
                XCTAssertTrue(text.contains(message), "\(text) should mention \(message)")
            }
        }
    }

    func testEmptyFixtureHasEmptySections() throws {
        let inbox = try Fixture.load(from: write(#"{ "viewerLogin": "x" }"#)).inbox(now: referenceDate)
        for section in InboxSection.allCases {
            XCTAssertEqual(inbox.count(section), 0)
        }
    }

    func testTheBundledFixturesLoad() throws {
        let fixtures = repositoryRoot.appendingPathComponent("Fixtures")
        let showcase = try Fixture.load(from: fixtures.appendingPathComponent("showcase.json")).inbox(now: referenceDate)
        XCTAssertEqual(InboxSection.allCases.map(showcase.count), [2, 2, 1, 2, 3, 3, 0])

        XCTAssertEqual(try Fixture.load(from: fixtures.appendingPathComponent("empty.json")).inbox().count(.needsYourReview), 0)

        let error = try Fixture.load(from: fixtures.appendingPathComponent("error.json"))
        XCTAssertEqual(error.error, "GitHub rejected the token (401). Set a new one.")
        XCTAssertEqual(try error.inbox().count(.needsYourReview), 1)
    }

    @MainActor
    func testTheAppShowsAFixtureAndItsError() throws {
        let app = AppDelegate()
        app.installStatusItemForTesting()
        defer { app.removeStatusItemForTesting() }
        app.loadFixtureForTesting(repositoryRoot.appendingPathComponent("Fixtures/error.json"))
        XCTAssertEqual(app.inboxForTesting?.count(.needsYourReview), 1)
        XCTAssertEqual(app.lastErrorForTesting?.localizedDescription, "GitHub rejected the token (401). Set a new one.")

        app.loadFixtureForTesting(repositoryRoot.appendingPathComponent("Fixtures/showcase.json"))
        XCTAssertNil(app.lastErrorForTesting)
        XCTAssertEqual(app.inboxForTesting?.count(.readyToMerge), 3)
    }

    @MainActor
    func testTheAppReportsABrokenFixture() throws {
        let app = AppDelegate()
        app.installStatusItemForTesting()
        defer { app.removeStatusItemForTesting() }
        app.loadFixtureForTesting(try write("not json"))
        XCTAssertNil(app.inboxForTesting)
        XCTAssertNotNil(app.lastErrorForTesting)
    }
}
