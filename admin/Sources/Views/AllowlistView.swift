import SwiftUI
import UIKit

struct AllowlistView: View {
    @EnvironmentObject var config: AppConfig
    @State private var entries: Loadable<[AllowEntry]> = .idle
    @State private var showAdd = false
    @State private var pendingDelete: AllowEntry?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background()
                content
                if let toast { toastView(toast) }
            }
            .navigationTitle("授权名单")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAdd = true } label: { Label("添加授权", systemImage: "plus") }
                        Button { Task { await seed() } } label: { Label("导入 worker.js 现有名单", systemImage: "square.and.arrow.down") }
                        Button { Task { await load() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .refreshable { await load() }
            .task { if case .idle = entries { await load() } }
            .sheet(isPresented: $showAdd) { AddAllowSheet { await load() } }
            .confirmationDialog("移出名单后，该账号下次联网核对就会失效（最慢约 1 天）。",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                if let e = pendingDelete {
                    Button("移出授权", role: .destructive) { Task { await remove(e) } }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !config.hasAdmin {
            ScrollView { NeedsConfig(text: "需要先在设置里填 Worker 地址和管理口令").glassCard().padding(16) }
        } else {
            switch entries {
            case .idle, .loading:
                ProgressView("加载中…")
            case .failed(let m):
                ScrollView { VStack(spacing: 12) {
                    ErrorBanner(message: m)
                    Button { Task { await load() } } label: { Label("重试", systemImage: "arrow.clockwise") }
                        .buttonStyle(.glass)
                }.padding(16) }
            case .loaded(let list):
                if list.isEmpty { emptyState } else { listView(list) }
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                Text("KV 名单是空的").font(.headline)
                Text("点右上角「导入 worker.js 现有名单」把原来的测试账号灌进来，或直接「添加授权」。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { Task { await seed() } } label: {
                    Label("导入现有名单", systemImage: "square.and.arrow.down").font(.headline)
                }.buttonStyle(.glassProminent).padding(.top, 4)
            }.padding(28)
        }
    }

    private func listView(_ list: [AllowEntry]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("共 \(list.count) 个授权账号").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button { showAdd = true } label: { Label("添加", systemImage: "plus.circle.fill") }
                        .buttonStyle(.glass)
                }
                ForEach(list) { e in row(e) }
            }.padding(16)
        }
    }

    private func row(_ e: AllowEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.good)
                Text(e.note.isEmpty ? "未命名账号" : e.note).font(.headline)
                Spacer()
                Button(role: .destructive) { pendingDelete = e } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.bad)
                }.buttonStyle(.plain)
            }
            Text(shortHash(e.account))
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            if e.addedAt > 0 {
                Text("加入于 \(absoluteTime(e.addedAt))").font(.caption).foregroundStyle(.tertiary)
            }
        }.glassCard()
        .contextMenu {
            Button { UIPasteboard.general.string = e.account } label: { Label("复制完整哈希", systemImage: "doc.on.doc") }
        }
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.black.opacity(0.8), in: Capsule())
                .padding(.bottom, 24)
        }.transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task { try? await Task.sleep(nanoseconds: 1_800_000_000); withAnimation { toast = nil } }
    }

    private func load() async {
        entries = .loading
        do { entries = .loaded(try await config.worker.listAllow()) }
        catch { entries = .failed((error as? APIError)?.message ?? error.localizedDescription) }
    }

    private func remove(_ e: AllowEntry) async {
        do { try await config.worker.removeAllow(account: e.account); flash("已移出授权"); await load() }
        catch { flash((error as? APIError)?.message ?? "删除失败") }
        pendingDelete = nil
    }

    private func seed() async {
        do { let r = try await config.worker.seed(); flash("已导入 \(r.added) 个，共 \(r.count) 个"); await load() }
        catch { flash((error as? APIError)?.message ?? "导入失败") }
    }
}

// 添加授权：输 wxid 自动算哈希，或直接粘 64 位哈希。
struct AddAllowSheet: View {
    @EnvironmentObject var config: AppConfig
    @Environment(\.dismiss) private var dismiss
    var onDone: () async -> Void

    enum Mode: String, CaseIterable { case wxid = "按 wxid", hash = "按哈希" }
    @State private var mode: Mode = .wxid
    @State private var wxid = ""
    @State private var hash = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    private var computedHash: String { wxid.isEmpty ? "" : WXGCrypto.accountHash(forWXID: wxid) }
    private var canSubmit: Bool {
        mode == .wxid ? !wxid.trimmingCharacters(in: .whitespaces).isEmpty
                      : WXGCrypto.isAccountHash(hash.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("方式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                if mode == .wxid {
                    Section("微信号 wxid") {
                        TextField("wxid_xxxxxxxxxxxxxx", text: $wxid)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        if !computedHash.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("算出的账号哈希").font(.caption).foregroundStyle(.secondary)
                                Text(computedHash).font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(Theme.accent).textSelection(.enabled)
                            }
                        }
                    }
                    Section { Text("哈希 = SHA-256(\"WXGLiquidGlass.license.v1:\" + wxid)，和插件、服务器算法一致。wxid 不会上传，只上传哈希。")
                        .font(.caption).foregroundStyle(.secondary) }
                } else {
                    Section("账号哈希（64 位十六进制）") {
                        TextField("a7a5fc72…", text: $hash, axis: .vertical)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }

                Section("备注（可选）") {
                    TextField("例如：张三 / 2026 年付费", text: $note)
                }

                if let error {
                    Section { Text(error).font(.subheadline).foregroundStyle(Theme.bad) }
                }
            }
            .navigationTitle("添加授权")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "添加中…" : "添加") { Task { await submit() } }
                        .disabled(!canSubmit || busy)
                }
            }
        }
    }

    private func submit() async {
        busy = true; error = nil
        do {
            if mode == .wxid {
                _ = try await config.worker.addAllow(wxid: wxid.trimmingCharacters(in: .whitespaces), note: note)
            } else {
                _ = try await config.worker.addAllow(account: hash.trimmingCharacters(in: .whitespaces).lowercased(), note: note)
            }
            await onDone(); dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
        busy = false
    }
}
