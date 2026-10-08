import Combine
import Foundation
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    let isAvailable: Bool
    let unavailableReason: String
    private let service: LoginItemService

    init(service: LoginItemService? = nil,
         isDevelopment: Bool = BuildIdentity.isDevelopment,
         isAppBundle: Bool = Bundle.main.bundleURL.pathExtension == "app") {
        self.service = service ?? SystemLoginItemService()
        isAvailable = !isDevelopment && isAppBundle
        unavailableReason = isDevelopment ? "DEV · 开机自启已禁用" : "请使用打包后的 MiniStats.app 设置开机自启"
        refresh()
    }

    // Pending approval is registered, but cannot launch until the user permits it.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { isAvailable && status == .requiresApproval }

    var detail: String? {
        if !isAvailable { return unavailableReason }
        if requiresApproval { return "需要在系统设置的登录项中允许 MiniStats" }
        if status == .notFound { return "系统未找到应用，请将 MiniStats.app 放到应用程序目录后重试" }
        return nil
    }

    func refresh() {
        guard isAvailable else { return }
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        errorMessage = nil
        refresh()
        guard enabled != isOn else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = "开机自启设置失败：\(error.localizedDescription)"
        }
        refresh()
    }

    func openSettings() {
        guard isAvailable else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
