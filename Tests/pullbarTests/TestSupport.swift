import Foundation
@testable import pullbar

/// A fixed point in time, so tests never depend on the clock.
let referenceDate = ISO8601DateFormatter().date(from: "2026-03-10T12:00:00Z")!

/// A pull request with sensible defaults; override only what a test is about.
func makePR(
    id: String = UUID().uuidString,
    number: Int = 1,
    title: String = "A pull request",
    isDraft: Bool = false,
    updatedAt: Date = referenceDate,
    author: String = "octocat",
    repository: String = "acme/app",
    reviewDecision: ReviewDecision? = nil,
    mergeable: Mergeable = .mergeable,
    checks: Checks? = nil,
    commentCount: Int = 0,
    isInMergeQueue: Bool = false
) -> PullRequest {
    PullRequest(
        id: id,
        number: number,
        title: title,
        url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
        isDraft: isDraft,
        updatedAt: updatedAt,
        author: author,
        repository: repository,
        reviewDecision: reviewDecision,
        mergeable: mergeable,
        checks: checks,
        commentCount: commentCount,
        isInMergeQueue: isInMergeQueue
    )
}

func checks(_ state: Checks.State, passed: Int = 1, total: Int = 1) -> Checks {
    Checks(state: state, total: total, passed: passed)
}

// MARK: - A fake GitHub GraphQL endpoint

/// Answers every request made through `StubGitHub.session()` with the handler
/// installed by the test, and records the requests.
final class StubGitHub: URLProtocol {
    struct Request {
        let url: URL?
        let method: String?
        let headers: [String: String]
        let json: [String: Any]

        var query: String { json["query"] as? String ?? "" }
        var variables: [String: Any] { json["variables"] as? [String: Any] ?? [:] }
    }

    typealias Handler = (Request) -> (status: Int, body: Any)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var recorded: [Request] = []
    nonisolated(unsafe) private static var headers: [String: String] = [:]

    /// `headers` are sent with every response, e.g. rate-limit headers.
    static func install(headers: [String: String] = [:], _ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            self.headers = headers
            recorded = []
        }
    }

    static var requests: [Request] { lock.withLock { recorded } }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGitHub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let recordedRequest = Request(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            json: json
        )
        let (handler, headers) = Self.lock.withLock { () -> (Handler?, [String: String]) in
            Self.recorded.append(recordedRequest)
            return (Self.handler, Self.headers)
        }
        let (status, payload) = handler?(recordedRequest) ?? (500, "no stub installed")
        let data: Data
        if let text = payload as? String {
            data = Data(text.utf8)
        } else {
            data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// MARK: - GraphQL response builders

/// One pull request node as the search query returns it.
func prNode(
    id: String = "PR_1",
    number: Int = 1,
    title: String = "A pull request",
    repository: String = "acme/app",
    author: String? = "octocat",
    isDraft: Bool? = false,
    updatedAt: String = "2026-03-10T12:00:00Z",
    mergeable: String? = "MERGEABLE",
    reviewDecision: String? = nil,
    comments: Int? = 0,
    rollup: [String: Any]? = nil
) -> [String: Any] {
    var node: [String: Any] = [
        "id": id,
        "number": number,
        "title": title,
        "url": "https://github.com/\(repository)/pull/\(number)",
        "updatedAt": updatedAt,
        "repository": ["nameWithOwner": repository],
        "commits": ["nodes": [["commit": ["statusCheckRollup": rollup as Any? ?? NSNull()]]]],
    ]
    if let isDraft { node["isDraft"] = isDraft }
    if let mergeable { node["mergeable"] = mergeable }
    if let reviewDecision { node["reviewDecision"] = reviewDecision }
    if let author { node["author"] = ["login": author] }
    if let comments { node["comments"] = ["totalCount": comments] }
    return node
}

/// A status check rollup for the given check runs and statuses.
func rollup(state: String, contexts: [[String: Any]]) -> [String: Any] {
    return [
        "state": state,
        "contexts": [
            "totalCount": contexts.count,
            "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
            "nodes": contexts,
        ],
    ]
}

func checkRun(_ conclusion: String?) -> [String: Any] {
    ["__typename": "CheckRun", "status": "COMPLETED", "conclusion": conclusion as Any? ?? NSNull()]
}

func statusContext(_ state: String) -> [String: Any] {
    ["__typename": "StatusContext", "state": state]
}

func searchResponse(
    viewer: String = "octocat",
    nodes: [Any],
    hasNextPage: Bool = false,
    endCursor: String? = nil
) -> [String: Any] {
    [
        "data": [
            "viewer": ["login": viewer],
            "search": [
                "issueCount": nodes.count,
                "pageInfo": ["hasNextPage": hasNextPage, "endCursor": endCursor as Any? ?? NSNull()],
                "nodes": nodes,
            ],
        ],
    ]
}
