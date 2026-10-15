import Foundation
import Combine

// 运行期配置。非敏感项（Worker 地址、CF Account ID）放 UserDefaults；
// 敏感项（管理口令、CF API Token）放 Keychain。
final class AppConfig: ObservableObject {
    static let defaultWorker = "https://xyylwc.kvgdth56kf.workers.dev"

    @Published var workerBaseURL: String { didSet { UserDefaults.standard.set(workerBaseURL, forKey: "workerBaseURL") } }
    @Published var cfAccountId: String   { didSet { UserDefaults.standard.set(cfAccountId, forKey: "cfAccountId") } }
    @Published var adminToken: String    { didSet { Keychain.set(adminToken, for: "adminToken") } }
    @Published var cfToken: String       { didSet { Keychain.set(cfToken, for: "cfToken") } }

    init() {
        let d = UserDefaults.standard
        workerBaseURL = d.string(forKey: "workerBaseURL") ?? AppConfig.defaultWorker
        cfAccountId   = d.string(forKey: "cfAccountId") ?? ""
        adminToken    = Keychain.get("adminToken") ?? ""
        cfToken       = Keychain.get("cfToken") ?? ""
    }

    var worker: WorkerClient { WorkerClient(baseURL: normalizedWorkerURL, adminToken: adminToken) }
    var cloudflare: CloudflareClient { CloudflareClient(token: cfToken, accountId: cfAccountId) }

    var normalizedWorkerURL: String {
        var s = workerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    var hasAdmin: Bool { !adminToken.isEmpty && !normalizedWorkerURL.isEmpty }
    var hasCloudflare: Bool { !cfToken.isEmpty && !cfAccountId.isEmpty }
}
