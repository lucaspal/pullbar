import Foundation

/// A made-up inbox loaded from a JSON file instead of GitHub, for screenshots
/// and for checking how the menu renders. Start the app with
/// `--fixture <file.json>`; see `Fixtures/` for examples.
///
/// Times are relative ("3h" ago), so a fixture looks the same whenever it is
/// shown. The three lists mirror the inbox searches: `direct` review requests,
/// `teams` review requests, and your own `authored` pull requests, which are
/// sorted into sections by the same rules as real data.
struct Fixture: Decodable {
    struct PR: Decodable {
        let number: Int
        let title: String
        let repository: String
        let author: String
        /// How long ago it was updated: a number and a unit, e.g. "45m",
        /// "3h", "2d", "5w".
        let updated: String
        var isDraft: Bool?
        var isInMergeQueue: Bool?
        /// "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED", or omitted.
        var reviewDecision: String?
        /// "MERGEABLE" (default), "CONFLICTING", or "UNKNOWN".
        var mergeable: String?
        var checks: FixtureChecks?
        var comments: Int?
    }

    struct FixtureChecks: Decodable {
        /// "SUCCESS", "FAILURE", "ERROR", "PENDING", or "EXPECTED".
        let state: String
        let passed: Int
        let total: Int
    }

    let viewerLogin: String
    var direct: [PR]?
    var teams: [PR]?
    var authored: [PR]?
    /// Shows this message as a failed refresh, alongside the inbox.
    var error: String?

    struct Invalid: LocalizedError {
        let errorDescription: String?
    }

    /// The fixture path given with `--fixture`, if any.
    static func path(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--fixture"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func load(from url: URL) throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func inbox(now: Date = Date()) throws -> Inbox {
        let direct = try (direct ?? []).map { try $0.pullRequest(now: now) }
        let teams = try (teams ?? []).map { try $0.pullRequest(now: now) }
        return Inbox.build(
            reviewRequested: direct + teams,
            userReviewRequested: direct,
            authored: try (authored ?? []).map { try $0.pullRequest(now: now) },
            viewerLogin: viewerLogin
        )
    }
}

extension Fixture.PR {
    func pullRequest(now: Date) throws -> PullRequest {
        let id = "\(repository)#\(number)"
        func invalid(_ message: String) -> Fixture.Invalid {
            Fixture.Invalid(errorDescription: "Fixture \(id): \(message)")
        }

        guard let url = URL(string: "https://github.com/\(repository)/pull/\(number)") else {
            throw invalid("invalid repository")
        }
        guard let age = Self.seconds(updated) else {
            throw invalid("updated must look like 45m, 3h, 2d or 5w, not \(updated)")
        }
        var decision: ReviewDecision?
        if let reviewDecision {
            guard let value = ReviewDecision(rawValue: reviewDecision) else {
                throw invalid("unknown reviewDecision \(reviewDecision)")
            }
            decision = value
        }
        guard let mergeState = Mergeable(rawValue: mergeable ?? "MERGEABLE") else {
            throw invalid("unknown mergeable \(mergeable ?? "")")
        }
        var checkState: Checks?
        if let checks {
            guard let state = Checks.State(rawValue: checks.state) else {
                throw invalid("unknown checks state \(checks.state)")
            }
            checkState = Checks(state: state, total: checks.total, passed: checks.passed)
        }

        return PullRequest(
            id: id,
            number: number,
            title: title,
            url: url,
            isDraft: isDraft ?? false,
            updatedAt: now.addingTimeInterval(-age),
            author: author,
            repository: repository,
            reviewDecision: decision,
            mergeable: mergeState,
            checks: checkState,
            commentCount: comments ?? 0,
            isInMergeQueue: isInMergeQueue ?? false
        )
    }

    /// "45m" -> 2700. Units: m(inutes), h(ours), d(ays), w(eeks).
    static func seconds(_ text: String) -> TimeInterval? {
        let units: [Character: TimeInterval] = ["m": 60, "h": 3600, "d": 86400, "w": 604_800]
        guard let unit = text.last, let size = units[unit], let count = Double(text.dropLast()) else {
            return nil
        }
        return count * size
    }
}
