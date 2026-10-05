import XCTest
@testable import pullbar

final class InboxBatchTests: XCTestCase {
    private func client() -> GitHubClient {
        GitHubClient(token: "t", session: StubGitHub.session())
    }

    private func result(
        requested: [Any] = [], requestedHasNext: Bool = false, requestedCursor: String? = nil,
        direct: [Any] = [], directHasNext: Bool = false, directCursor: String? = nil,
        authored: [Any] = [], authoredHasNext: Bool = false, authoredCursor: String? = nil
    ) -> [String: Any] {
        func search(_ nodes: [Any], _ hasNext: Bool, _ cursor: String?) -> [String: Any] {
            [
                "issueCount": nodes.count,
                "pageInfo": ["hasNextPage": hasNext, "endCursor": cursor as Any? ?? NSNull()],
                "nodes": nodes,
            ]
        }

        return [
            "data": [
                "viewer": ["login": "octocat"],
                "rateLimit": [
                    "limit": 5000, "remaining": 4998, "used": 2,
                    "cost": 2, "resetAt": "2026-03-10T13:00:00Z",
                ],
                "requested": search(requested, requestedHasNext, requestedCursor),
                "direct": search(direct, directHasNext, directCursor),
                "authored": search(authored, authoredHasNext, authoredCursor),
            ],
        ]
    }

    func testInboxUsesOneGraphQLRequestAndBuildsTheSameSections() async throws {
        StubGitHub.install { _ in
            (200, self.result(
                requested: [prNode(id: "direct"), prNode(id: "team", number: 2)],
                direct: [["id": "direct"]],
                authored: [prNode(id: "draft", number: 3, isDraft: true)]
            ))
        }

        let inbox = try await InboxService(client: client()).fetch(window: .all)

        XCTAssertEqual(StubGitHub.requests.count, 1)
        let request = try XCTUnwrap(StubGitHub.requests.first)
        XCTAssertTrue(request.query.contains("requested: search"))
        XCTAssertTrue(request.query.contains("direct: search"))
        XCTAssertTrue(request.query.contains("authored: search"))
        XCTAssertTrue(request.query.contains("requested: search(query: $requestedQuery, type: ISSUE, first: 100, after: $requestedAfter)"))
        XCTAssertEqual(inbox.pullRequests(in: .needsYourReview).map(\.id), ["direct"])
        XCTAssertEqual(inbox.pullRequests(in: .needsTeamsReview).map(\.id), ["team"])
        XCTAssertEqual(inbox.pullRequests(in: .yourDrafts).map(\.id), ["draft"])
        XCTAssertEqual(inbox.viewerLogin, "octocat")
        XCTAssertEqual(inbox.apiUsage?.lastRefreshRequests, 1)
    }

    func testPagingRequestsOnlyAliasesThatHaveAnotherPage() async throws {
        StubGitHub.install { request in
            if request.query.contains("requested: search") && request.variables["requestedAfter"] == nil {
                return (200, self.result(
                    requested: [prNode(id: "direct-1"), prNode(id: "requested-1", number: 2)],
                    requestedHasNext: true, requestedCursor: "R2",
                    direct: [["id": "direct-1"]],
                    authored: [prNode(id: "authored-1")], authoredHasNext: true, authoredCursor: "A2"
                ))
            }
            return (200, self.result(
                requested: [prNode(id: "requested-2", number: 2)],
                authored: [prNode(id: "authored-2", number: 2)]
            ))
        }

        let inbox = try await InboxService(client: client()).fetch(window: .all)

        XCTAssertEqual(StubGitHub.requests.count, 2)
        let second = try XCTUnwrap(StubGitHub.requests.last)
        XCTAssertTrue(second.query.contains("requested: search"))
        XCTAssertTrue(second.query.contains("authored: search"))
        XCTAssertFalse(second.query.contains("direct: search"))
        XCTAssertEqual(second.variables["requestedAfter"] as? String, "R2")
        XCTAssertEqual(second.variables["authoredAfter"] as? String, "A2")
        XCTAssertEqual(inbox.pullRequests(in: .needsTeamsReview).map(\.id).sorted(), ["requested-1", "requested-2"])
        XCTAssertEqual(inbox.pullRequests(in: .needsYourReview).map(\.id), ["direct-1"])
        XCTAssertEqual(inbox.pullRequests(in: .readyToMerge).map(\.id).sorted(), ["authored-1", "authored-2"])
        XCTAssertEqual(inbox.apiUsage?.lastRefreshRequests, 2)
    }
}

final class RefreshPolicyTests: XCTestCase {
    func testMenuOpenRefreshesOnlyWhenNoRecentSuccessfulFetchExists() {
        XCTAssertTrue(RefreshPolicy.shouldRefreshOnMenuOpen(lastSuccess: nil, lastError: nil, now: referenceDate))
        XCTAssertFalse(RefreshPolicy.shouldRefreshOnMenuOpen(
            lastSuccess: referenceDate.addingTimeInterval(-29), lastError: nil, now: referenceDate
        ))
        XCTAssertTrue(RefreshPolicy.shouldRefreshOnMenuOpen(
            lastSuccess: referenceDate.addingTimeInterval(-30), lastError: nil, now: referenceDate
        ))
        XCTAssertTrue(RefreshPolicy.shouldRefreshOnMenuOpen(
            lastSuccess: referenceDate, lastError: GitHubError.unauthorized, now: referenceDate
        ))
    }

    func testLowBudgetUsesFifteenMinuteAutomaticIntervalUntilReset() {
        let resetAt = referenceDate.addingTimeInterval(3600)
        XCTAssertEqual(
            RefreshPolicy.interval(configured: 120, usage: usage(remaining: 499, resetAt: resetAt), now: referenceDate),
            900
        )
        XCTAssertEqual(
            RefreshPolicy.interval(configured: 300, usage: usage(remaining: 499, resetAt: resetAt), now: referenceDate),
            900
        )
        XCTAssertEqual(
            RefreshPolicy.interval(configured: 120, usage: usage(remaining: 500, resetAt: resetAt), now: referenceDate),
            120
        )
        XCTAssertEqual(
            RefreshPolicy.interval(configured: 120, usage: usage(remaining: 100, resetAt: referenceDate), now: referenceDate),
            120
        )
        XCTAssertEqual(
            RefreshPolicy.interval(
                configured: 120,
                usage: usage(remaining: 100, resetAt: referenceDate.addingTimeInterval(300)),
                now: referenceDate
            ),
            301
        )
    }

    func testRateLimitCooldownBlocksRequestsUntilReset() {
        let resetAt = referenceDate.addingTimeInterval(60)
        XCTAssertFalse(RefreshPolicy.mayRefresh(blockedUntil: resetAt, now: referenceDate))
        XCTAssertFalse(RefreshPolicy.mayRefresh(blockedUntil: resetAt, now: resetAt.addingTimeInterval(-1)))
        XCTAssertTrue(RefreshPolicy.mayRefresh(blockedUntil: resetAt, now: resetAt))
        XCTAssertTrue(RefreshPolicy.mayRefresh(blockedUntil: nil, now: referenceDate))
        XCTAssertEqual(RefreshPolicy.retryDate(resetAt: nil, now: referenceDate), referenceDate.addingTimeInterval(900))
    }
}

private func usage(remaining: Int, resetAt: Date) -> APIUsage {
    APIUsage(limit: 5000, remaining: remaining, resetAt: resetAt, lastRefreshCost: 1, lastRefreshRequests: 1)
}
