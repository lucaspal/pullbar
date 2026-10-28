import Foundation
import XCTest

/// Exercise the packaging boundary against real plists, without signing keys.
final class UpdatePackagingTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func configure(key: String, repository: String = "https://github.com/example/Fork") throws -> (Int32, [String: Any]) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist = directory.appendingPathComponent("Info.plist")
        let input: [String: Any] = ["PullbarSourceRepository": repository]
        try PropertyListSerialization.data(fromPropertyList: input, format: .xml, options: 0).write(to: plist)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("Packaging/configure-updates.sh").path, plist.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["SPARKLE_PUBLIC_KEY": key]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let result = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        return (process.terminationStatus, result)
    }

    func testPublicKeyEnablesTheBuildsOwnRepositoryFeed() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let (status, plist) = try configure(key: key)
        XCTAssertEqual(status, 0)
        XCTAssertEqual(plist["SUPublicEDKey"] as? String, key)
        XCTAssertEqual(plist["SUFeedURL"] as? String,
                       "https://github.com/example/Fork/releases/latest/download/appcast.xml")
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(plist["SURequireSignedFeed"] as? Bool, true)
    }

    func testNoKeyLeavesDevelopmentBuildsWithoutAnUpdateFeed() throws {
        let (status, plist) = try configure(key: "")
        XCTAssertEqual(status, 0)
        XCTAssertNil(plist["SUPublicEDKey"])
        XCTAssertNil(plist["SUFeedURL"])
    }

    func testInvalidKeysAndRepositoriesFailPackaging() throws {
        for key in ["not-base64", Data(repeating: 1, count: 31).base64EncodedString()] {
            XCTAssertNotEqual(try configure(key: key).0, 0)
        }
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertNotEqual(try configure(key: key, repository: "https://example.com/Fork").0, 0)
    }
}
