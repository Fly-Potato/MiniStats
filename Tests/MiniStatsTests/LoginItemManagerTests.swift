import ServiceManagement
import XCTest
@testable import MiniStats

final class LoginItemManagerTests: XCTestCase {
    private final class Service: LoginItemService {
        var status: SMAppService.Status = .notRegistered
        var registrationStatus: SMAppService.Status = .enabled
        var failure: Error?
        var registrations = 0
        var removals = 0

        func register() throws {
            registrations += 1
            if let failure { throw failure }
            status = registrationStatus
        }

        func unregister() throws {
            removals += 1
            if let failure { throw failure }
            status = .notRegistered
        }
    }

    func testOptInRegistersAndDisablingUnregisters() {
        let service = Service()
        let manager = LoginItemManager(service: service, isDevelopment: false, isAppBundle: true)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertFalse(manager.isOn)
        manager.setEnabled(true)
        XCTAssertTrue(manager.isOn)
        manager.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        manager.setEnabled(false)
        XCTAssertFalse(manager.isOn)
        XCTAssertEqual(service.removals, 1)
    }

    func testPendingApprovalRemainsRegisteredAndCanBeRemoved() {
        let service = Service()
        service.registrationStatus = .requiresApproval
        let manager = LoginItemManager(service: service, isDevelopment: false, isAppBundle: true)
        manager.setEnabled(true)
        XCTAssertTrue(manager.isOn)
        XCTAssertTrue(manager.requiresApproval)
        XCTAssertNotNil(manager.detail)
        manager.setEnabled(false)
        XCTAssertFalse(manager.requiresApproval)
        XCTAssertEqual(service.removals, 1)
    }

    func testFailuresKeepActualSystemStateAndRetryClearsError() {
        let service = Service()
        service.failure = NSError(domain: "LoginItemTests", code: 1)
        let manager = LoginItemManager(service: service, isDevelopment: false, isAppBundle: true)
        manager.setEnabled(true)
        XCTAssertFalse(manager.isOn)
        XCTAssertNotNil(manager.errorMessage)
        service.failure = nil
        manager.setEnabled(true)
        XCTAssertNil(manager.errorMessage)
        service.failure = NSError(domain: "LoginItemTests", code: 2)
        manager.setEnabled(false)
        XCTAssertTrue(manager.isOn)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testRefreshReflectsChangesFromSystemSettings() {
        let service = Service()
        service.status = .enabled
        let manager = LoginItemManager(service: service, isDevelopment: false, isAppBundle: true)
        XCTAssertTrue(manager.isOn)
        service.status = .requiresApproval
        manager.refresh()
        XCTAssertTrue(manager.requiresApproval)
        service.status = .notRegistered
        manager.refresh()
        XCTAssertFalse(manager.isOn)
    }

    func testDevelopmentAndUnbundledBuildsNeverRegister() {
        for (development, bundled) in [(true, true), (false, false)] {
            let service = Service()
            let manager = LoginItemManager(service: service, isDevelopment: development, isAppBundle: bundled)
            manager.setEnabled(true)
            manager.refresh()
            XCTAssertFalse(manager.isAvailable)
            XCTAssertFalse(manager.isOn)
            XCTAssertNotNil(manager.detail)
            XCTAssertEqual(service.registrations, 0)
            XCTAssertEqual(service.removals, 0)
        }
    }
}
