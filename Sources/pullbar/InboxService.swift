import Foundation

/// Fetches the three searches that github.com/pulls/inbox is made of and folds
/// them into sections.
struct InboxService {
    let client: GitHubClient

    func fetch(window: UpdatedWindow) async throws -> Inbox {
        let base = ["is:open", "archived:false", "sort:updated-desc", window.searchQualifier]
            .compactMap { $0 }
            .joined(separator: " ")

        let result = try await client.fetchInbox(baseQuery: base)
        let direct = result.requestedPullRequests.filter { result.directlyRequestedIDs.contains($0.id) }
        return Inbox.build(
            reviewRequested: result.requestedPullRequests,
            userReviewRequested: direct,
            authored: result.authoredPullRequests,
            viewerLogin: result.viewerLogin,
            apiUsage: Self.apiUsage(of: result)
        )
    }

    static func apiUsage(of result: GitHubClient.InboxSearchResult) -> APIUsage? {
        guard let limit = result.rateLimit else { return nil }
        return APIUsage(
            limit: limit.limit,
            remaining: limit.remaining,
            resetAt: limit.resetAt,
            lastRefreshCost: result.cost,
            lastRefreshRequests: result.requests
        )
    }

    /// The budget left after this refresh (the lowest the searches saw) and
    /// what the refresh cost in total; nil when GitHub reported no budget.
    static func apiUsage(of results: [GitHubClient.SearchResult]) -> APIUsage? {
        guard let lowest = results.compactMap(\.rateLimit).min(by: { $0.remaining < $1.remaining }) else { return nil }
        return APIUsage(
            limit: lowest.limit,
            remaining: lowest.remaining,
            resetAt: lowest.resetAt,
            lastRefreshCost: results.reduce(0) { $0 + $1.cost },
            lastRefreshRequests: results.reduce(0) { $0 + $1.requests }
        )
    }
}
