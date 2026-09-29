import XCTest
@testable import Louppe

final class EarlyUserFeedbackTests: XCTestCase {
    func testCampaignIsLimitedToTheOneTenReleaseSeries() {
        for version in ["1.10", "1.10.0", "1.10.1"] {
            XCTAssertTrue(EarlyUserFeedback.shouldPresent(version: version, hasBeenShown: false))
        }
        for version in ["", "1", "1.9.0", "1.11.0", "1.100.0", "2.10.0"] {
            XCTAssertFalse(EarlyUserFeedback.shouldPresent(version: version, hasBeenShown: false))
        }
    }

    func testShownPreferenceSurvivesRelaunchAndSuppressesPatchReminders() throws {
        let suite = "EarlyUserFeedbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(EarlyUserFeedback.shouldPresent(
            version: "1.10.0", hasBeenShown: defaults.bool(forKey: EarlyUserFeedback.shownKey)
        ))
        defaults.set(true, forKey: EarlyUserFeedback.shownKey)
        let relaunchedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        for version in ["1.10.0", "1.10.1"] {
            XCTAssertFalse(EarlyUserFeedback.shouldPresent(
                version: version,
                hasBeenShown: relaunchedDefaults.bool(forKey: EarlyUserFeedback.shownKey)
            ))
        }
    }
}
