import AppKit
import XCTest
@testable import pullbar

final class UpdateConfigurationTests: XCTestCase {
    private let key = Data(repeating: 1, count: 32).base64EncodedString()
    private let feed = "https://github.com/lucaspal/Pullbar/releases/latest/download/appcast.xml"

    private func reason(path: String = "/Applications/pullbar.app", key: String? = nil,
                        feed: String? = nil) -> String? {
        AppUpdater.unavailableReason(bundleURL: URL(fileURLWithPath: path), info: [
            "SUPublicEDKey": key ?? self.key,
            "SUFeedURL": feed ?? self.feed,
        ])
    }

    func testConfiguredAppCanUseSparkleWithoutDeveloperID() {
        XCTAssertNil(reason())
        XCTAssertNil(reason(path: "/Users/example/Applications/pullbar.app"))
    }

    func testDevelopmentBinaryDoesNotStartAnUpdater() {
        XCTAssertEqual(reason(path: "/tmp/pullbar"), "Updates are available in the installed app bundle.")
    }

    func testTemporaryAndHomebrewInstallsAreNotReplaced() {
        XCTAssertEqual(reason(path: "/private/var/AppTranslocation/abc/d/pullbar.app"),
                       "Move pullbar to Applications before updating.")
        for path in ["/opt/homebrew/Cellar/pullbar/1.0/pullbar.app", "/opt/homebrew/Caskroom/pullbar/1.0/pullbar.app"] {
            XCTAssertEqual(reason(path: path), "Update this installation with Homebrew.")
        }
    }

    func testMissingOrInvalidPublicKeyDisablesUpdates() {
        for invalid in ["", "not-a-key", Data(repeating: 1, count: 31).base64EncodedString()] {
            XCTAssertEqual(reason(key: invalid), "Update signing is not configured for this build.")
        }
    }

    func testFeedMustUseHTTPS() {
        for invalid in ["", "http://example.com/appcast.xml", "file:///tmp/appcast.xml"] {
            XCTAssertEqual(reason(feed: invalid), "A secure update feed is not configured for this build.")
        }
    }

    @MainActor
    func testUnconfiguredMenuItemExplainsWhyItIsDisabled() throws {
        let app = AppDelegate()
        app.rebuildMenuForTesting()
        let item = try XCTUnwrap(app.menuForTesting.items.first { $0.title == "Check for updates…" })
        XCTAssertFalse(item.isEnabled)
        XCTAssertEqual(item.toolTip, "Updates are available in the installed app bundle.")
    }
}
