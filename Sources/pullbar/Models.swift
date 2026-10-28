import Foundation

enum ReviewDecision: String {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum Mergeable: String {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

/// The combined state of the checks on a pull request's head commit,
/// as GitHub's `statusCheckRollup` reports it.
struct Checks: Hashable {
    enum State: String {
        case success = "SUCCESS"
        case failure = "FAILURE"
        case error = "ERROR"
        case pending = "PENDING"
        case expected = "EXPECTED"
    }

    let state: State
    /// Total number of check runs and commit statuses.
    let total: Int
    /// Number of them that passed (success, neutral or skipped).
    let passed: Int

    var isFailing: Bool { state == .failure || state == .error }
    var isPending: Bool { state == .pending || state == .expected }
}

struct PullRequest: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let updatedAt: Date
    let author: String
    let repository: String
    let reviewDecision: ReviewDecision?
    let mergeable: Mergeable
    let checks: Checks?
    let commentCount: Int
    let isInMergeQueue: Bool

    /// The user or organisation that owns the repository: "acme" for "acme/api".
    var owner: String {
        String(repository.split(separator: "/", maxSplits: 1).first ?? Substring(repository))
    }

    var hasFailingChecks: Bool { checks?.isFailing ?? false }

    /// Something on the author's side blocks this PR: a review asked for
    /// changes, checks fail, or it conflicts with its base.
    var needsAction: Bool {
        reviewDecision == .changesRequested || hasFailingChecks || mergeable == .conflicting
    }

    /// Not queued, approved (or no review required), checks green (or none), no conflict.
    var isReadyToMerge: Bool {
        let reviewOK = reviewDecision == .approved || reviewDecision == nil
        let checksOK = checks == nil || checks?.state == .success
        return !isInMergeQueue && reviewOK && checksOK && mergeable != .conflicting
    }

    /// Review or merge queue status shown in the inbox's status column.
    var reviewStatusLabel: String {
        if isDraft { return "Not ready" }
        if isInMergeQueue { return "Queued" }
        switch reviewDecision {
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .reviewRequired: return "Awaiting approval"
        case nil: return "Review not required"
        }
    }
}

/// Inbox sections, with queued authored pull requests following ready to merge.
enum InboxSection: CaseIterable {
    case needsYourReview
    case needsTeamsReview
    case yourDrafts
    case waitingForReviewOrChecks
    case needsAction
    case readyToMerge
    case queued

    var title: String {
        switch self {
        case .needsYourReview: return "Needs your review"
        case .needsTeamsReview: return "Needs your teams' review"
        case .yourDrafts: return "Your drafts"
        case .waitingForReviewOrChecks: return "Waiting for review or checks"
        case .needsAction: return "Needs action"
        case .readyToMerge: return "Ready to merge"
        case .queued: return "Queued"
        }
    }

    var emptyText: String {
        switch self {
        case .needsYourReview, .needsTeamsReview: return "Nothing to review"
        case .yourDrafts: return "No drafts"
        case .waitingForReviewOrChecks: return "All caught up"
        case .needsAction: return "Nothing needs your action"
        case .readyToMerge: return "Nothing ready to merge"
        case .queued: return "Nothing queued"
        }
    }
}

/// GitHub's GraphQL budget after the last refresh, and what that refresh cost.
struct APIUsage: Equatable {
    let limit: Int
    let remaining: Int
    let resetAt: Date
    /// Points and requests the last refresh used.
    let lastRefreshCost: Int
    let lastRefreshRequests: Int

    var used: Int { limit - remaining }
    /// Less than 10% of the budget left.
    var isLow: Bool { remaining * 10 < limit }
}

struct Inbox {
    let sections: [InboxSection: [PullRequest]]
    let viewerLogin: String
    let fetchedAt: Date
    /// Nil when unknown.
    var apiUsage: APIUsage? = nil

    func pullRequests(in section: InboxSection) -> [PullRequest] {
        sections[section] ?? []
    }

    func count(_ section: InboxSection) -> Int {
        pullRequests(in: section).count
    }

    /// Pull requests grouped by repository owner, for the menu's subheadings.
    /// Most recent first: groups are ordered by their most recently updated pull
    /// request (ties by owner name), and each group lists newest first.
    static func groupedByOwner(_ prs: [PullRequest]) -> [(owner: String, pullRequests: [PullRequest])] {
        let newestFirst: (PullRequest, PullRequest) -> Bool = { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.repository != rhs.repository {
                return lhs.repository.localizedStandardCompare(rhs.repository) == .orderedAscending
            }
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.id < rhs.id
        }
        return Dictionary(grouping: prs, by: \.owner)
            .map { (owner: $0.key, pullRequests: $0.value.sorted(by: newestFirst)) }
            .sorted { a, b in
                let newestA = a.pullRequests[0].updatedAt, newestB = b.pullRequests[0].updatedAt
                return newestA != newestB ? newestA > newestB : a.owner.localizedStandardCompare(b.owner) == .orderedAscending
            }
    }

    /// Splits the three raw searches into the seven inbox sections.
    ///
    /// - `userReviewRequested`: `user-review-requested:@me` — asked directly.
    /// - `reviewRequested`: `review-requested:@me` — directly or via a team;
    ///   whatever is not in the first list is a team request.
    /// - `authored`: `author:@me`, split by draft / queued / blocked / ready / waiting.
    static func build(
        reviewRequested: [PullRequest],
        userReviewRequested: [PullRequest],
        authored: [PullRequest],
        viewerLogin: String,
        now: Date = Date(),
        apiUsage: APIUsage? = nil
    ) -> Inbox {
        let direct = Set(userReviewRequested.map(\.id))
        let teams = reviewRequested.filter { !direct.contains($0.id) }

        var drafts: [PullRequest] = []
        var waiting: [PullRequest] = []
        var action: [PullRequest] = []
        var ready: [PullRequest] = []
        var queued: [PullRequest] = []
        for pr in authored {
            if pr.isDraft {
                drafts.append(pr)
            } else if pr.isInMergeQueue {
                queued.append(pr)
            } else if pr.needsAction {
                action.append(pr)
            } else if pr.isReadyToMerge {
                ready.append(pr)
            } else {
                waiting.append(pr)
            }
        }

        let byUpdated: (PullRequest, PullRequest) -> Bool = { $0.updatedAt > $1.updatedAt }
        return Inbox(
            sections: [
                .needsYourReview: userReviewRequested.sorted(by: byUpdated),
                .needsTeamsReview: teams.sorted(by: byUpdated),
                .yourDrafts: drafts.sorted(by: byUpdated),
                .waitingForReviewOrChecks: waiting.sorted(by: byUpdated),
                .needsAction: action.sorted(by: byUpdated),
                .readyToMerge: ready.sorted(by: byUpdated),
                .queued: queued.sorted(by: byUpdated),
            ],
            viewerLogin: viewerLogin,
            fetchedAt: now,
            apiUsage: apiUsage
        )
    }
}
