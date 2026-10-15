import SwiftUI

struct RootView: View {
    @EnvironmentObject var config: AppConfig

    var body: some View {
        TabView {
            Tab("概览", systemImage: "shield.lefthalf.filled") { OverviewView() }
            Tab("名单", systemImage: "person.2.badge.key.fill") { AllowlistView() }
            Tab("活动", systemImage: "waveform.path.ecg") { ActivityView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)   // iOS 26：下滑收起玻璃 Tab 栏
    }
}

// 统一的异步加载状态。
enum Loadable<T> {
    case idle, loading, loaded(T), failed(String)
    var value: T? { if case .loaded(let v) = self { return v }; return nil }
}

// 错误条。
struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            Text(message).font(.subheadline).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// 未配置提示。
struct NeedsConfig: View {
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill").font(.largeTitle).foregroundStyle(Theme.accent)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("到「设置」里填好后下拉刷新").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
