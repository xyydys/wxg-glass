import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledField(title: "Worker 地址", text: $config.workerBaseURL,
                                 placeholder: AppConfig.defaultWorker, mono: true)
                    SecureLabeledField(title: "管理口令 ADMIN_TOKEN", text: $config.adminToken,
                                       placeholder: "worker 的 ADMIN_TOKEN Secret")
                } header: { Text("授权服务器") } footer: {
                    Text("管理口令 = 你在 Cloudflare Worker 的 Settings → Variables and Secrets 里设的 ADMIN_TOKEN。用来读写名单和核对记录。")
                }

                Section {
                    LabeledField(title: "Account ID", text: $config.cfAccountId,
                                 placeholder: "32 位账号 ID", mono: true)
                    SecureLabeledField(title: "API Token", text: $config.cfToken,
                                       placeholder: "权限含 Account Analytics:Read")
                } header: { Text("Cloudflare 分析（看请求曲线，可选）") } footer: {
                    Text("Account ID 在 Workers & Pages 概览右侧。API Token 在 My Profile → API Tokens 创建，权限选 Account Analytics → Read。只用于读取请求量，不改任何东西。")
                }

                Section {
                    Button { Task { await test() } } label: {
                        HStack {
                            Image(systemName: "checkmark.shield")
                            Text(testing ? "测试中…" : "测试连接")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }.disabled(testing || !config.hasAdmin)
                    if let testResult {
                        Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.subheadline).foregroundStyle(testOK ? Theme.good : Theme.bad)
                    }
                }

                Section {
                    HStack { Text("密钥存储"); Spacer(); Text("iOS Keychain").foregroundStyle(.secondary) }
                    HStack { Text("版本"); Spacer(); Text(appVersion).foregroundStyle(.secondary) }
                } footer: {
                    Text("管理口令和 API Token 只保存在本机 Keychain，不会上传到任何地方。")
                }
            }
            .navigationTitle("设置")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func test() async {
        testing = true; testResult = nil
        do {
            let p = try await config.worker.ping()
            testOK = p.admin
            testResult = p.admin ? "连接成功，当前 \(p.allowCount ?? 0) 个授权账号" : "连接到了，但口令无效"
        } catch {
            testOK = false
            testResult = (error as? APIError)?.message ?? error.localizedDescription
        }
        testing = false
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var mono: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .font(mono ? .system(.body, design: .monospaced) : .body)
        }
    }
}

struct SecureLabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    @State private var reveal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Group {
                    if reveal { TextField(placeholder, text: $text) }
                    else { SecureField(placeholder, text: $text) }
                }
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .font(.system(.body, design: .monospaced))
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
    }
}
