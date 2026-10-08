import AppKit
import Combine
import Sparkle

final class UpdateManager: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var status: String
    private var controller: SPUStandardUpdaterController?
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "本地构建"

    init() {
        if BuildIdentity.isDevelopment {
            status = "DEV · 更新已禁用"
            return
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty else {
            status = "此构建未配置更新"
            return
        }
        status = "自动检查间隔：24 小时"
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main).assign(to: &$automaticChecks)
        do {
            try controller.updater.start()
        } catch {
            status = "更新器启动失败：\(error.localizedDescription)"
            self.controller = nil
        }
    }

    var isConfigured: Bool { controller != nil }

    func check() {
        guard canCheck else { return }
        // Menu bar utilities may have no key window when showing update dialogs.
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
