import XCTest
@testable import MiniStats

final class UpdateManagerTests: XCTestCase {
    func testDevelopmentBuildNeverStartsUpdater() {
        #if DEBUG
        let updates = UpdateManager()
        XCTAssertFalse(updates.isConfigured)
        XCTAssertFalse(updates.canCheck)
        XCTAssertFalse(updates.automaticChecks)
        updates.setAutomaticChecks(true)
        updates.check()
        XCTAssertFalse(updates.isConfigured)
        XCTAssertFalse(updates.automaticChecks)
        XCTAssertEqual(updates.status, "DEV · 更新已禁用")
        #endif
    }
}
