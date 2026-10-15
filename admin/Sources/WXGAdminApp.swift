import SwiftUI

// WXG 授权台 · 管理 wxg-glass 解锁服务器的授权名单与核对活动。
// 全部密钥（管理口令 / Cloudflare Token）只存 iOS Keychain，不落明文、不进日志。
@main
struct WXGAdminApp: App {
    @StateObject private var config = AppConfig()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(config)
                .tint(Theme.accent)
                .preferredColorScheme(nil)   // 跟随系统
        }
    }
}
