import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// 调用 wxg-glass worker 的管理接口 /v1/admin/*（Bearer = ADMIN_TOKEN）。
struct WorkerClient {
    let baseURL: String
    let adminToken: String

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError(message: "Worker 地址无效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        if auth { req.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw APIError(message: "网络错误：\(error.localizedDescription)") }
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "无响应") }
        if !(200..<300).contains(http.statusCode) {
            let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            let hint: String
            switch http.statusCode {
            case 401: hint = "管理口令不对（401）"
            case 503: hint = serverMsg ?? "管理接口未开启（503）：worker 需绑定 KV 且设置 ADMIN_TOKEN"
            default:  hint = serverMsg ?? "HTTP \(http.statusCode)"
            }
            throw APIError(message: hint)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(message: "返回解析失败：\(error.localizedDescription)") }
    }

    // GET /  —— 不需要鉴权的自检
    func health() async throws -> Health {
        try decode(Health.self, try await request("/", auth: false))
    }

    // GET /v1/admin/ping —— 验证管理口令
    func ping() async throws -> AdminPing {
        try decode(AdminPing.self, try await request("/v1/admin/ping"))
    }

    // GET /v1/admin/allow
    func listAllow() async throws -> [AllowEntry] {
        struct Resp: Codable { var count: Int; var entries: [AllowEntry] }
        return try decode(Resp.self, try await request("/v1/admin/allow")).entries
    }

    // POST /v1/admin/allow —— account 或 wxid 二选一
    @discardableResult
    func addAllow(account: String? = nil, wxid: String? = nil, note: String) async throws -> AddAllowResult {
        var body: [String: Any] = ["note": note]
        if let account { body["account"] = account }
        if let wxid { body["wxid"] = wxid }
        return try decode(AddAllowResult.self, try await request("/v1/admin/allow", method: "POST", body: body))
    }

    // DELETE /v1/admin/allow/<account>
    func removeAllow(account: String) async throws {
        _ = try await request("/v1/admin/allow/\(account)", method: "DELETE")
    }

    // POST /v1/admin/seed —— 把 worker.js 里的常量名单导入 KV
    @discardableResult
    func seed() async throws -> SeedResult {
        try decode(SeedResult.self, try await request("/v1/admin/seed", method: "POST", body: [:]))
    }

    // GET /v1/admin/activity
    func activity(limit: Int = 200) async throws -> AdminActivity {
        try decode(AdminActivity.self, try await request("/v1/admin/activity?limit=\(limit)"))
    }
}
