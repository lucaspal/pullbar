import AppKit
import XCTest
@testable import pullbar

private let resetDate = ISO8601DateFormatter().date(from: "2026-03-10T14:05:00Z")!

private func rateLimitJSON(remaining: Int, cost: Int = 1, limit: Int = 5000) -> [String: Any] {
    ["limit": limit, "remaining": remaining, "used": limit - remaining, "cost": cost, "resetAt": "2026-03-10T14:05:00Z"]
}

private func usage(remaining: Int, limit: Int = 5000, cost: Int = 2, requests: Int = 1) -> APIUsage {
    APIUsage(limit: limit, remaining: remaining, resetAt: resetDate, lastRefreshCost: cost, lastRefreshRequests: requests)
}

final class APIUsageModelTests: XCTestCase {
    func testUsedAndLow() {
        XCTAssertEqual(usage(remaining: 4373).used, 627)
        XCTAssertFalse(usage(remaining: 500).isLow, "exactly 10% left is not low yet")
        XCTAssertTrue(usage(remaining: 499).isLow)
        XCTAssertTrue(usage(remaining: 0).isLow)
    }
}

final class RateLimitClientTests: XCTestCase {
    private func client() -> GitHubClient { GitHubClient(token: "t", session: StubGitHub.session()) }

    func testTheQueryAsksForTheBudget() async throws {
        StubGitHub.install { _ in (200, searchResponse(nodes: [])) }
        _ = try await client().searchPullRequests("q")
        XCTAssertTrue(try XCTUnwrap(StubGitHub.requests.first).query.contains("rateLimit { limit remaining used cost resetAt }"))
    }

    func testBudgetAndCostAreReadAcrossPages() async throws {
        StubGitHub.install { request in
            if request.variables["after"] == nil {
                var page = searchResponse(nodes: [prNode(id: "A")], hasNextPage: true, endCursor: "C1")
                page["data"] = (page["data"] as! [String: Any]).merging(["rateLimit": rateLimitJSON(remaining: 4000, cost: 1)]) { $1 }
                return (200, page)
            }
            var page = searchResponse(nodes: [prNode(id: "B")])
            page["data"] = (page["data"] as! [String: Any]).merging(["rateLimit": rateLimitJSON(remaining: 3999, cost: 1)]) { $1 }
            return (200, page)
        }
        let result = try await client().searchPullRequests("q")
        XCTAssertEqual(result.requests, 2)
        XCTAssertEqual(result.cost, 2)
        XCTAssertEqual(result.rateLimit?.remaining, 3999, "the budget after the last page")
        XCTAssertEqual(result.rateLimit?.resetAt, resetDate)
    }

    func testNoBudgetInTheResponse() async throws {
        StubGitHub.install { _ in (200, searchResponse(nodes: [])) }
        let result = try await client().searchPullRequests("q")
        XCTAssertNil(result.rateLimit)
        XCTAssertEqual(result.cost, 0)
        XCTAssertEqual(result.requests, 1)
    }

    func testHTTPRateLimitWithResetTime() async {
        StubGitHub.install(headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(resetDate.timeIntervalSince1970))"]) { _ in
            (403, "API rate limit exceeded")
        }
        await assertRateLimited(resetAt: resetDate)
    }

    func testHTTP429WithoutHeaders() async {
        StubGitHub.install { _ in (429, "slow down") }
        await assertRateLimited(resetAt: nil)
    }

    func testHTTP429UsesRetryAfterHTTPDate() async {
        StubGitHub.install(headers: ["Retry-After": "Tue, 10 Mar 2026 14:05:00 GMT"]) { _ in
            (429, "slow down")
        }
        await assertRateLimited(resetAt: resetDate)
    }

    func testHTTP403UsesRetryAfterEvenWhenBudgetRemains() async {
        let startedAt = Date()
        StubGitHub.install(headers: ["x-ratelimit-remaining": "4000", "Retry-After": "60"]) { _ in
            (403, "secondary rate limit")
        }
        do {
            _ = try await client().searchPullRequests("q")
            XCTFail("expected a secondary rate-limit error")
        } catch GitHubError.rateLimited(let resetAt) {
            let retryDelay = try? XCTUnwrap(resetAt).timeIntervalSince(startedAt)
            XCTAssertGreaterThanOrEqual(retryDelay ?? 0, 59)
            XCTAssertLessThanOrEqual(retryDelay ?? .infinity, 61)
        } catch {
            XCTFail("expected a rate-limit error, got \(error)")
        }
    }

    func testForbiddenForOtherReasonsIsAnHTTPError() async {
        StubGitHub.install(headers: ["x-ratelimit-remaining": "4000"]) { _ in (403, "forbidden") }
        do {
            _ = try await client().searchPullRequests("q")
            XCTFail("expected an error")
        } catch GitHubError.http(let code, _) {
            XCTAssertEqual(code, 403)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testGraphQLRateLimitedError() async {
        StubGitHub.install { _ in (200, ["data": NSNull(), "errors": [["type": "RATE_LIMITED", "message": "API rate limit exceeded"]]]) }
        await assertRateLimited(resetAt: nil)
    }

    func testGraphQLRateLimitedErrorUsesResetFromPartialData() async {
        StubGitHub.install { _ in
            (200, [
                "data": ["rateLimit": rateLimitJSON(remaining: 0)],
                "errors": [["type": "RATE_LIMITED", "message": "API rate limit exceeded"]],
            ])
        }
        await assertRateLimited(resetAt: resetDate)
    }

    func testRateLimitMessages() {
        XCTAssertEqual(GitHubError.rateLimited(resetAt: nil).errorDescription, "GitHub API limit reached. Try again later.")
        let text = GitHubError.rateLimited(resetAt: resetDate).errorDescription ?? ""
        XCTAssertEqual(text, "GitHub API limit reached. It resets at \(resetDate.formatted(date: .omitted, time: .shortened)).")
    }

    private func assertRateLimited(resetAt expected: Date?, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await client().searchPullRequests("q")
            XCTFail("expected a rate-limit error", file: file, line: line)
        } catch GitHubError.rateLimited(let resetAt) {
            XCTAssertEqual(resetAt, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}

final class APIUsageServiceTests: XCTestCase {
    private func result(remaining: Int?, cost: Int, requests: Int) -> GitHubClient.SearchResult {
        GitHubClient.SearchResult(
            viewerLogin: "", pullRequests: [],
            rateLimit: remaining.map { GQL.RateLimit(limit: 5000, remaining: $0, used: 5000 - $0, cost: cost, resetAt: resetDate) },
            cost: cost, requests: requests
        )
    }

    func testTheRefreshAddsUpItsSearches() throws {
        let combined = try XCTUnwrap(InboxService.apiUsage(of: [
            result(remaining: 4003, cost: 1, requests: 1),
            result(remaining: 4001, cost: 2, requests: 2),
            result(remaining: 4002, cost: 1, requests: 1),
        ]))
        XCTAssertEqual(combined.remaining, 4001, "the lowest budget any search saw")
        XCTAssertEqual(combined.lastRefreshCost, 4)
        XCTAssertEqual(combined.lastRefreshRequests, 4)
        XCTAssertEqual(combined.resetAt, resetDate)
    }

    func testNoBudgetReportedNoUsage() {
        XCTAssertNil(InboxService.apiUsage(of: [result(remaining: nil, cost: 0, requests: 1)]))
    }

    func testFetchCarriesTheUsageIntoTheInbox() async throws {
        StubGitHub.install { _ in
            func emptySearch() -> [String: Any] {
                ["issueCount": 0, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": [Any]()]
            }
            return (200, ["data": [
                "viewer": ["login": "octocat"],
                "rateLimit": rateLimitJSON(remaining: 4373, cost: 2),
                "requested": emptySearch(), "direct": emptySearch(), "authored": emptySearch(),
            ]])
        }
        let inbox = try await InboxService(client: GitHubClient(token: "t", session: StubGitHub.session())).fetch(window: .all)
        XCTAssertEqual(inbox.apiUsage?.used, 627)
        XCTAssertEqual(inbox.apiUsage?.lastRefreshRequests, 1, "three aliased searches share one request")
        XCTAssertEqual(inbox.apiUsage?.lastRefreshCost, 2)
    }
}

@MainActor
final class APIUsageMenuTests: XCTestCase {
    private func refreshLine(_ app: AppDelegate) throws -> NSMenuItem {
        try XCTUnwrap(app.menuForTesting.items.first { ($0.attributedTitle?.string ?? $0.title).hasPrefix("Refresh now") })
    }

    private func inbox(_ usage: APIUsage?, fetchedAt: Date = Date()) -> Inbox {
        Inbox.build(reviewRequested: [], userReviewRequested: [], authored: [], viewerLogin: "octocat", now: fetchedAt, apiUsage: usage)
    }

    func testTheRefreshLineShowsTheBudget() throws {
        let app = AppDelegate()
        app.inboxForTesting = inbox(usage(remaining: 4373, cost: 2, requests: 1))
        app.rebuildMenuForTesting()
        let item = try refreshLine(app)
        let text = try XCTUnwrap(item.attributedTitle?.string)
        let time = resetDate.formatted(date: .omitted, time: .shortened)
        XCTAssertTrue(text.hasSuffix(" · signed in as octocat · API \(627.formatted()) of \(5000.formatted()) used, resets \(time)"), text)
        XCTAssertEqual(item.toolTip, "The last refresh used 2 API points in 1 request. \(4373.formatted()) of \(5000.formatted()) points are left until \(time), shared with other apps that use the same GitHub token.")
        XCTAssertEqual(AppDelegate.apiUsageToolTip(usage(remaining: 10, requests: 4)).contains("in 4 requests"), true)
    }

    func testALowBudgetIsOrangeAndInTheMenuBarTooltip() throws {
        let app = AppDelegate()
        let low = usage(remaining: 120)
        app.inboxForTesting = inbox(low)
        app.rebuildMenuForTesting()
        let title = try XCTUnwrap(try refreshLine(app).attributedTitle)
        let range = (title.string as NSString).range(of: "API budget low — refreshing less often: ")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(title.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor, .systemOrange)

        let toolTip = AppDelegate.statusText(inbox: inbox(low), error: nil)?.toolTip ?? ""
        XCTAssertTrue(toolTip.hasSuffix(AppDelegate.apiUsageText(low)), toolTip)
        XCTAssertFalse((AppDelegate.statusText(inbox: inbox(usage(remaining: 4000)), error: nil)?.toolTip ?? "").contains("API"))
    }

    func testNoBudgetKnownNothingShown() throws {
        let app = AppDelegate()
        app.inboxForTesting = inbox(nil)
        app.rebuildMenuForTesting()
        XCTAssertFalse(try XCTUnwrap(try refreshLine(app).attributedTitle?.string).contains("API"))
    }

    func testJustFetchedReadsJustNow() throws {
        let app = AppDelegate()
        // A fetch time a moment in the future must not read "in 0 seconds".
        app.inboxForTesting = inbox(nil, fetchedAt: Date().addingTimeInterval(0.5))
        app.rebuildMenuForTesting()
        let text = try XCTUnwrap(try refreshLine(app).attributedTitle?.string)
        XCTAssertTrue(text.contains("Updated just now"), text)

        // Nor a fetch a fraction of a second ago "0 seconds ago".
        app.inboxForTesting = inbox(nil, fetchedAt: Date().addingTimeInterval(-0.3))
        app.rebuildMenuForTesting()
        let recent = try XCTUnwrap(try refreshLine(app).attributedTitle?.string)
        XCTAssertTrue(recent.contains("Updated just now"), recent)

        app.inboxForTesting = inbox(nil, fetchedAt: Date().addingTimeInterval(-120))
        app.rebuildMenuForTesting()
        XCTAssertTrue(try XCTUnwrap(try refreshLine(app).attributedTitle?.string).contains("Updated 2 minutes ago"))
    }
}
