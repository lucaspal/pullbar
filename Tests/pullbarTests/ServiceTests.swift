import AppKit
import XCTest
@testable import pullbar

final class InboxServiceTests: XCTestCase {
    /// Answers the three aliases in the combined inbox query.
    private func installInbox() {
        StubGitHub.install { request in
            func search(_ nodes: [Any]) -> [String: Any] {
                ["issueCount": nodes.count, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": nodes]
            }
            return (200, ["data": [
                "viewer": ["login": "octocat"],
                "rateLimit": ["limit": 5000, "remaining": 4998, "used": 2, "cost": 2, "resetAt": "2026-03-10T14:05:00Z"],
                "requested": search([prNode(id: "direct"), prNode(id: "team")]),
                "direct": search([["id": "direct"]]),
                "authored": search([prNode(id: "mine", isDraft: true)]),
            ]])
        }
    }

    func testFetchRunsTheThreeInboxSearchesInOneRequest() async throws {
        installInbox()
        let service = InboxService(client: GitHubClient(token: "t", session: StubGitHub.session()))
        _ = try await service.fetch(window: .all)

        XCTAssertEqual(StubGitHub.requests.count, 1)
        let request = try XCTUnwrap(StubGitHub.requests.first)
        XCTAssertTrue(request.query.contains("requested: search"))
        XCTAssertTrue(request.query.contains("direct: search"))
        XCTAssertTrue(request.query.contains("authored: search"))
        XCTAssertEqual(request.variables["requestedQuery"] as? String, "is:pr is:open archived:false sort:updated-desc review-requested:@me")
        XCTAssertEqual(request.variables["directQuery"] as? String, "is:pr is:open archived:false sort:updated-desc user-review-requested:@me")
        XCTAssertEqual(request.variables["authoredQuery"] as? String, "is:pr is:open archived:false sort:updated-desc author:@me")
    }

    func testFetchAddsTheUpdatedFilter() async throws {
        installInbox()
        let service = InboxService(client: GitHubClient(token: "t", session: StubGitHub.session()))
        _ = try await service.fetch(window: .week)
        let qualifier = try XCTUnwrap(UpdatedWindow.week.searchQualifier)
        let request = try XCTUnwrap(StubGitHub.requests.first)
        for key in ["requestedQuery", "directQuery", "authoredQuery"] {
            let q = request.variables[key] as? String ?? ""
            XCTAssertTrue(q.contains(" \(qualifier) "), q)
        }
    }

    func testFetchSortsResultsIntoSections() async throws {
        installInbox()
        let service = InboxService(client: GitHubClient(token: "t", session: StubGitHub.session()))
        let inbox = try await service.fetch(window: .month)
        XCTAssertEqual(inbox.pullRequests(in: .needsYourReview).map(\.id), ["direct"])
        XCTAssertEqual(inbox.pullRequests(in: .needsTeamsReview).map(\.id), ["team"])
        XCTAssertEqual(inbox.pullRequests(in: .yourDrafts).map(\.id), ["mine"])
        // The viewer comes from the authored search.
        XCTAssertEqual(inbox.viewerLogin, "octocat")
    }

    func testFetchFailsWhenAnySearchFails() async {
        StubGitHub.install { _ in (401, "no") }
        let service = InboxService(client: GitHubClient(token: "t", session: StubGitHub.session()))
        do {
            _ = try await service.fetch(window: .all)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? GitHubError)?.errorDescription, GitHubError.unauthorized.errorDescription)
        }
    }
}

final class KeychainTests: XCTestCase {
    private var service = ""

    override func setUp() {
        super.setUp()
        // A throwaway item: never the real "pullbar GitHub token".
        service = "pullbar-tests-\(UUID().uuidString)"
    }

    override func tearDown() {
        Keychain.deleteToken(service: service)
        super.tearDown()
    }

    func testRealItemIsNotTheTestItem() {
        XCTAssertEqual(Keychain.defaultService, "pullbar GitHub token")
        XCTAssertNotEqual(service, Keychain.defaultService)
    }

    func testWriteReadOverwriteDelete() throws {
        XCTAssertNil(Keychain.readToken(service: service))
        do {
            try Keychain.writeToken("first", service: service)
        } catch let error as KeychainError where error.status == errSecInteractionNotAllowed {
            throw XCTSkip("keychain is locked on this machine")
        }
        XCTAssertEqual(Keychain.readToken(service: service), "first")

        try Keychain.writeToken("second", service: service)
        XCTAssertEqual(Keychain.readToken(service: service), "second")

        Keychain.deleteToken(service: service)
        XCTAssertNil(Keychain.readToken(service: service))
    }

    func testStoredWhitespaceIsTrimmedOnRead() throws {
        try Keychain.writeToken("  ghp_abc \n", service: service)
        XCTAssertEqual(Keychain.readToken(service: service), "ghp_abc")
        try Keychain.writeToken("   ", service: service)
        XCTAssertNil(Keychain.readToken(service: service))
    }

    func testNormalizedToken() {
        XCTAssertEqual(Keychain.normalizedToken("ghp_x"), "ghp_x")
        XCTAssertEqual(Keychain.normalizedToken("\t ghp_x \n"), "ghp_x")
        XCTAssertNil(Keychain.normalizedToken(""))
        XCTAssertNil(Keychain.normalizedToken(" \n"))
    }

    func testErrorDescription() {
        XCTAssertFalse((KeychainError(status: errSecItemNotFound).errorDescription ?? "").isEmpty)
    }
}

final class TokenProviderTests: XCTestCase {
    func testReadsAndTrimsTheCommandOutput() async {
        let token = await TokenProvider.fromGhCLI(command: "printf '  gho_token \\n'")
        XCTAssertEqual(token, "gho_token")
    }

    func testFailingCommandGivesNoToken() async {
        let token = await TokenProvider.fromGhCLI(command: "echo gho_token; exit 1")
        XCTAssertNil(token)
    }

    func testEmptyOutputGivesNoToken() async {
        let token = await TokenProvider.fromGhCLI(command: "printf ''")
        XCTAssertNil(token)
    }

    func testPasteShortcut() {
        XCTAssertTrue(TokenTextField.isPaste(flags: .command, characters: "v"))
        XCTAssertTrue(TokenTextField.isPaste(flags: .command, characters: "V"))
        // Caps Lock, Fn, and the keypad flag are not modifiers: they must not stop paste.
        XCTAssertTrue(TokenTextField.isPaste(flags: [.command, .capsLock], characters: "v"))
        XCTAssertTrue(TokenTextField.isPaste(flags: [.command, .function, .numericPad], characters: "v"))
        XCTAssertFalse(TokenTextField.isPaste(flags: [.command, .control], characters: "v"))

        XCTAssertFalse(TokenTextField.isPaste(flags: [.command, .shift], characters: "v"))
        XCTAssertFalse(TokenTextField.isPaste(flags: [.command, .option], characters: "v"))
        XCTAssertFalse(TokenTextField.isPaste(flags: [], characters: "v"))
        XCTAssertFalse(TokenTextField.isPaste(flags: .command, characters: "c"))
        XCTAssertFalse(TokenTextField.isPaste(flags: .command, characters: nil))
    }
}
