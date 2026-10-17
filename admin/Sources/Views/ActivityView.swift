import SwiftUI
import UIKit
import Charts

struct ActivityView: View {
    @EnvironmentObject var config: AppConfig
    @State private var window: CloudflareClient.Window = .day
    @State private var analytics: Loadable<AnalyticsSummary> = .idle
    @State private var checkins: Loadable<AdminActivity> = .idle

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background()
                ScrollView {
                    VStack(spacing: 16) {
                        cloudflareSection
                        checkinSection
                    }.padding(16)
                }
            }
            .navigationTitle("活动")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await loadAll() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    // 空格分隔，直接当 watermark_decode.mjs 的候选账号参数（含已踢出的账号）。
                    Button { copyAllHashes() } label: { Label("复制全部账号哈希", systemImage: "doc.on.doc") }
                        .disabled(checkins.value?.accounts.isEmpty ?? true)
                } label: { Image(systemName: "ellipsis.circle") } } }
            .refreshable { await loadAll() }
            .task { if case .idle = checkins { await loadAll() } }
        }
    }

    // ── Cloudflare 聚合分析 ──
    @ViewBuilder private var cloudflareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Cloudflare 请求量", icon: "chart.xyaxis.line")
                Spacer()
                Picker("", selection: $window) {
                    ForEach(CloudflareClient.Window.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 150)
                .onChange(of: window) { _ in Task { await loadAnalytics() } }
            }
            if !config.hasCloudflare {
                NeedsConfig(text: "填入 Cloudflare API Token 和 Account ID 后可看请求曲线")
            } else {
                switch analytics {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                case .failed(let m): ErrorBanner(message: m)
                case .loaded(let s): analyticsBody(s)
                }
            }
        }.glassCard()
    }

    @ViewBuilder private func analyticsBody(_ s: AnalyticsSummary) -> some View {
        HStack(spacing: 10) {
            StatTile(value: s.totalRequests.formatted(), label: "请求数", tint: Theme.accent, icon: "arrow.down.circle.fill")
            StatTile(value: s.totalErrors.formatted(), label: "错误数", tint: Theme.bad, icon: "exclamationmark.circle.fill")
            StatTile(value: String(format: "%.1f%%", s.errorRate * 100), label: "错误率", tint: Theme.warn, icon: "percent")
        }
        if s.totalRequests == 0 {
            Text("这段时间没有请求记录。").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
        } else {
            Chart(s.points) { p in
                AreaMark(x: .value("时间", p.date), y: .value("请求", p.requests))
                    .foregroundStyle(Theme.areaGradient).interpolationMethod(.catmullRom)
                LineMark(x: .value("时间", p.date), y: .value("请求", p.requests))
                    .foregroundStyle(Theme.accent).interpolationMethod(.catmullRom)
                if p.errors > 0 {
                    PointMark(x: .value("时间", p.date), y: .value("错误", p.errors))
                        .foregroundStyle(Theme.bad).symbolSize(28)
                }
            }
            .frame(height: 180)
            .chartXAxis { AxisMarks(preset: .aligned) }
            .padding(.top, 4)
        }
    }

    // ── 按账号核对记录（来自 worker 的 KV 日志）──
    @ViewBuilder private var checkinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "联网核对记录", icon: "person.badge.clock.fill")
            if !config.hasAdmin {
                NeedsConfig(text: "需要 Worker 地址与管理口令")
            } else {
                switch checkins {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                case .failed(let m): ErrorBanner(message: m)
                case .loaded(let a): checkinBody(a)
                }
            }
        }.glassCard()
    }

    @ViewBuilder private func checkinBody(_ a: AdminActivity) -> some View {
        if a.accounts.isEmpty && a.events.isEmpty {
            Text("还没有任何核对记录。只要有授权用户联网校验，这里就会出现。")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            if !a.accounts.isEmpty {
                Text("各账号最近状态").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(a.accounts) { acc in accountRow(acc) }
            }
            if !a.events.isEmpty {
                Divider().padding(.vertical, 4)
                Text("最近流水（\(a.events.count)）").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(a.events.prefix(40)) { ev in eventRow(ev) }
            }
        }
    }

    private func accountRow(_ acc: SeenAccount) -> some View {
        // FIX114（A）：近 7 天 >1 台设备 → 爆红（红点 + 红标“多设备 N”），但账号仍放行。
        let flagged = acc.flagged ?? false
        let active = acc.activeDevices ?? acc.deviceCount ?? 0
        return HStack(spacing: 12) {
            Circle().fill(flagged ? Theme.bad : (acc.lastResult == "ok" ? Theme.good : Theme.bad)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortHash(acc.account)).font(.system(.footnote, design: .monospaced))
                Text(flagged
                     ? "核对 \(acc.count) 次 · 在用 \(active) 台设备（上限 1）"
                     : "核对 \(acc.count) 次 · 设备 \(shortHash(acc.lastDevice))")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                StatusPill(text: flagged ? "多设备 \(active)" : (acc.lastResult == "ok" ? "通过" : "拒绝"),
                           kind: (flagged || acc.lastResult != "ok") ? .bad : .good)
                Text(relativeTime(acc.lastTs)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button { UIPasteboard.general.string = acc.account } label: { Label("复制完整哈希", systemImage: "doc.on.doc") }
        }
    }

    private func copyAllHashes() {
        guard let accounts = checkins.value?.accounts, !accounts.isEmpty else { return }
        UIPasteboard.general.string = accounts.map(\.account).joined(separator: " ")
    }

    private func eventRow(_ ev: ActivityEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ev.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.footnote).foregroundStyle(ev.allowed ? Theme.good : Theme.bad)
            Text(shortHash(ev.account)).font(.system(.caption, design: .monospaced))
            Spacer()
            Text(absoluteTime(ev.ts)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func loadAll() async {
        await loadCheckins()
        await loadAnalytics()
    }

    private func loadAnalytics() async {
        guard config.hasCloudflare else { return }
        analytics = .loading
        do { analytics = .loaded(try await config.cloudflare.fetch(window: window)) }
        catch { analytics = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }

    private func loadCheckins() async {
        guard config.hasAdmin else { return }
        checkins = .loading
        do { checkins = .loaded(try await config.worker.activity()) }
        catch { checkins = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }
}
