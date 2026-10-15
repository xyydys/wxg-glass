import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var config: AppConfig
    @State private var health: Loadable<Health> = .idle
    @State private var ping: Loadable<AdminPing> = .idle

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background()
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        if !config.hasAdmin {
                            NeedsConfig(text: "还没配置 Worker 地址或管理口令").glassCard()
                        } else {
                            serverCard
                            adminCard
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("授权台")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { refreshButton } }
            .refreshable { await load() }
            .task { if case .idle = health { await load() } }
        }
    }

    private var refreshButton: some View {
        Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title).foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading) {
                    Text("wxg-glass 解锁服务器").font(.headline)
                    Text(config.normalizedWorkerURL)
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }.glassCard()
    }

    @ViewBuilder private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "服务器自检", icon: "server.rack")
            switch health {
            case .loading, .idle:
                ProgressView().frame(maxWidth: .infinity)
            case .failed(let m):
                ErrorBanner(message: m)
            case .loaded(let h):
                HStack(spacing: 10) {
                    StatTile(value: h.ver ?? "—", label: "着色器版本", tint: Theme.accent, icon: "cube.fill")
                    StatTile(value: "\(h.allowCount ?? 0)", label: "授权人数", tint: Theme.accent2, icon: "person.fill")
                }
                VStack(spacing: 8) {
                    KeyValueRow(key: "签名私钥", value: h.signKey == "set" ? "已配置" : "缺失",
                                valueColor: h.signKey == "set" ? Theme.good : Theme.bad)
                    KeyValueRow(key: "名单来源", value: h.listSource == "kv" ? "KV（可远程管理）" : "worker.js 常量",
                                valueColor: h.listSource == "kv" ? Theme.good : Theme.warn)
                    KeyValueRow(key: "管理接口", value: h.admin == "set" ? "已开启" : "未开启",
                                valueColor: h.admin == "set" ? Theme.good : Theme.warn)
                    if let pub = h.pub, !pub.isEmpty {
                        KeyValueRow(key: "公钥", value: shortHash(pub), mono: true)
                    }
                }
                if h.listSource != "kv" {
                    Text("名单还在读 worker.js 常量：要远程改名单，先在设置里绑好 KV 并开启管理接口，再到「名单」页点「导入现有名单」。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.glassCard()
    }

    @ViewBuilder private var adminCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "管理口令", icon: "key.fill")
            switch ping {
            case .loading, .idle:
                ProgressView().frame(maxWidth: .infinity)
            case .failed(let m):
                ErrorBanner(message: m)
            case .loaded(let p):
                HStack {
                    Image(systemName: p.admin ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundStyle(p.admin ? Theme.good : Theme.bad)
                    Text(p.admin ? "口令有效，可管理名单" : "口令无效").font(.subheadline)
                    Spacer()
                    if let r = p.recheckAfter { StatusPill(text: "复查 \(r / 3600) 小时", kind: .neutral) }
                }
            }
        }.glassCard()
    }

    private func load() async {
        health = .loading
        ping = config.hasAdmin ? .loading : .idle
        do { health = .loaded(try await config.worker.health()) }
        catch { health = .failed((error as? APIError)?.message ?? error.localizedDescription) }
        guard config.hasAdmin else { return }
        do { ping = .loaded(try await config.worker.ping()) }
        catch { ping = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }
}
