import XCTest
@testable import pullbar

final class ChecksTests: XCTestCase {
    func testFailingStates() {
        XCTAssertTrue(checks(.failure).isFailing)
        XCTAssertTrue(checks(.error).isFailing)
        for state in [Checks.State.success, .pending, .expected] {
            XCTAssertFalse(checks(state).isFailing, "\(state)")
        }
    }

    func testPendingStates() {
        XCTAssertTrue(checks(.pending).isPending)
        XCTAssertTrue(checks(.expected).isPending)
        for state in [Checks.State.success, .failure, .error] {
            XCTAssertFalse(checks(state).isPending, "\(state)")
        }
    }
}

final class PullRequestTests: XCTestCase {
    func testHasFailingChecks() {
        XCTAssertTrue(makePR(checks: checks(.failure)).hasFailingChecks)
        XCTAssertFalse(makePR(checks: checks(.success)).hasFailingChecks)
        XCTAssertFalse(makePR(checks: nil).hasFailingChecks)
    }

    func testNeedsAction() {
        XCTAssertTrue(makePR(reviewDecision: .changesRequested).needsAction)
        XCTAssertTrue(makePR(checks: checks(.failure)).needsAction)
        XCTAssertTrue(makePR(checks: checks(.error)).needsAction)
        XCTAssertTrue(makePR(mergeable: .conflicting).needsAction)

        XCTAssertFalse(makePR().needsAction)
        XCTAssertFalse(makePR(reviewDecision: .reviewRequired, checks: checks(.pending)).needsAction)
        XCTAssertFalse(makePR(reviewDecision: .approved, mergeable: .unknown, checks: checks(.success)).needsAction)
    }

    func testIsReadyToMerge() {
        // Approved or no review required, checks green or none, no conflict.
        XCTAssertTrue(makePR(reviewDecision: .approved, checks: checks(.success)).isReadyToMerge)
        XCTAssertFalse(makePR(reviewDecision: .approved, checks: checks(.success), isInMergeQueue: true).isReadyToMerge)
        XCTAssertTrue(makePR(reviewDecision: nil, checks: nil).isReadyToMerge)
        XCTAssertTrue(makePR(reviewDecision: .approved, mergeable: .unknown).isReadyToMerge)

        XCTAssertFalse(makePR(reviewDecision: .reviewRequired, checks: checks(.success)).isReadyToMerge)
        XCTAssertFalse(makePR(reviewDecision: .changesRequested).isReadyToMerge)
        XCTAssertFalse(makePR(reviewDecision: .approved, checks: checks(.pending)).isReadyToMerge)
        XCTAssertFalse(makePR(reviewDecision: .approved, checks: checks(.failure)).isReadyToMerge)
        XCTAssertFalse(makePR(reviewDecision: .approved, mergeable: .conflicting).isReadyToMerge)
    }

    func testReviewStatusLabel() {
        XCTAssertEqual(makePR(reviewDecision: .approved).reviewStatusLabel, "Approved")
        XCTAssertEqual(makePR(reviewDecision: .changesRequested).reviewStatusLabel, "Changes requested")
        XCTAssertEqual(makePR(reviewDecision: .reviewRequired).reviewStatusLabel, "Awaiting approval")
        XCTAssertEqual(makePR(reviewDecision: nil).reviewStatusLabel, "Review not required")
        // A draft reads "Not ready" whatever its review state.
        XCTAssertEqual(makePR(isDraft: true, reviewDecision: .approved).reviewStatusLabel, "Not ready")
    }

    func testRawValuesMatchGitHub() {
        XCTAssertEqual(ReviewDecision(rawValue: "APPROVED"), .approved)
        XCTAssertEqual(ReviewDecision(rawValue: "CHANGES_REQUESTED"), .changesRequested)
        XCTAssertEqual(ReviewDecision(rawValue: "REVIEW_REQUIRED"), .reviewRequired)
        XCTAssertEqual(Mergeable(rawValue: "MERGEABLE"), .mergeable)
        XCTAssertEqual(Mergeable(rawValue: "CONFLICTING"), .conflicting)
        XCTAssertEqual(Mergeable(rawValue: "UNKNOWN"), .unknown)
        XCTAssertEqual(Checks.State(rawValue: "EXPECTED"), .expected)
    }
}

final class InboxSectionTests: XCTestCase {
    func testSectionOrder() {
        XCTAssertEqual(InboxSection.allCases, [
            .needsYourReview, .needsTeamsReview, .yourDrafts,
            .waitingForReviewOrChecks, .needsAction, .readyToMerge, .queued,
        ])
    }

    func testTitles() {
        XCTAssertEqual(InboxSection.allCases.map(\.title), [
            "Needs your review", "Needs your teams' review", "Your drafts",
            "Waiting for review or checks", "Needs action", "Ready to merge", "Queued",
        ])
    }

    func testEmptyTexts() {
        XCTAssertEqual(InboxSection.allCases.map(\.emptyText), [
            "Nothing to review", "Nothing to review", "No drafts",
            "All caught up", "Nothing needs your action", "Nothing ready to merge", "Nothing queued",
        ])
    }
}

final class InboxBuildTests: XCTestCase {
    private func build(
        requested: [PullRequest] = [],
        direct: [PullRequest] = [],
        authored: [PullRequest] = []
    ) -> Inbox {
        Inbox.build(
            reviewRequested: requested,
            userReviewRequested: direct,
            authored: authored,
            viewerLogin: "octocat",
            now: referenceDate
        )
    }

    func testDirectAndTeamRequests() {
        let direct = makePR(id: "direct")
        let team = makePR(id: "team")
        // review-requested:@me returns both; user-review-requested:@me only the direct one.
        let inbox = build(requested: [direct, team], direct: [direct])
        XCTAssertEqual(inbox.pullRequests(in: .needsYourReview).map(\.id), ["direct"])
        XCTAssertEqual(inbox.pullRequests(in: .needsTeamsReview).map(\.id), ["team"])
    }

    func testAuthoredPullRequestsAreSortedIntoOneSectionEach() {
        let draft = makePR(id: "draft", isDraft: true, checks: checks(.failure))
        let blocked = makePR(id: "blocked", reviewDecision: .approved, mergeable: .conflicting)
        let ready = makePR(id: "ready", reviewDecision: .approved, checks: checks(.success))
        let waiting = makePR(id: "waiting", reviewDecision: .reviewRequired, checks: checks(.success))
        let inbox = build(authored: [draft, blocked, ready, waiting])

        // Draft wins over everything, needs-action over ready-to-merge.
        XCTAssertEqual(inbox.pullRequests(in: .yourDrafts).map(\.id), ["draft"])
        XCTAssertEqual(inbox.pullRequests(in: .needsAction).map(\.id), ["blocked"])
        XCTAssertEqual(inbox.pullRequests(in: .readyToMerge).map(\.id), ["ready"])
        XCTAssertEqual(inbox.pullRequests(in: .waitingForReviewOrChecks).map(\.id), ["waiting"])
        XCTAssertTrue(inbox.pullRequests(in: .needsYourReview).isEmpty)
    }

    func testEverySectionIsSortedNewestFirst() {
        let old = makePR(id: "old", updatedAt: referenceDate.addingTimeInterval(-3600))
        let new = makePR(id: "new", updatedAt: referenceDate)
        let middle = makePR(id: "middle", updatedAt: referenceDate.addingTimeInterval(-60))
        let inbox = build(requested: [old, new, middle], direct: [old, new, middle], authored: [old, new, middle])
        XCTAssertEqual(inbox.pullRequests(in: .needsYourReview).map(\.id), ["new", "middle", "old"])
        XCTAssertEqual(inbox.pullRequests(in: .readyToMerge).map(\.id), ["new", "middle", "old"])
    }

    func testQueuedPullRequestsAreNewestFirstAndDraftsStayDrafts() {
        let old = makePR(id: "old", updatedAt: referenceDate.addingTimeInterval(-3600), isInMergeQueue: true)
        let new = makePR(id: "new", isInMergeQueue: true)
        let draft = makePR(id: "draft", isDraft: true, isInMergeQueue: true)
        let inbox = build(authored: [old, draft, new])
        XCTAssertEqual(inbox.pullRequests(in: .queued).map(\.id), ["new", "old"])
        XCTAssertEqual(inbox.pullRequests(in: .yourDrafts).map(\.id), ["draft"])
        XCTAssertEqual(draft.reviewStatusLabel, "Not ready")
    }

    func testCountsViewerAndTime() {
        let inbox = build(requested: [makePR(), makePR()], direct: [], authored: [makePR(isDraft: true)])
        XCTAssertEqual(inbox.count(.needsTeamsReview), 2)
        XCTAssertEqual(inbox.count(.yourDrafts), 1)
        XCTAssertEqual(inbox.count(.needsAction), 0)
        XCTAssertEqual(inbox.viewerLogin, "octocat")
        XCTAssertEqual(inbox.fetchedAt, referenceDate)
    }

    func testMissingSectionIsEmpty() {
        let inbox = Inbox(sections: [:], viewerLogin: "", fetchedAt: referenceDate)
        XCTAssertEqual(inbox.pullRequests(in: .readyToMerge).count, 0)
        XCTAssertEqual(inbox.count(.readyToMerge), 0)
    }
}
