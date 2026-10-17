import Foundation

struct AllowEntry: Codable, Identifiable, Hashable {
    let account: String
    var note: String
    var addedAt: Double
    var id: String { account }
}

struct SeenDevice: Codable, Hashable {
    let d: String
    let last: Double
}

struct SeenAccount: Codable, Identifiable, Hashable {
    let account: String
    var lastDevice: String
    var lastTs: Double
    var firstTs: Double
    var count: Int
    var lastResult: String
    // FIX114（A：设备治理）。老记录没有这些字段，解码为 nil，不影响兼容。
    var devices: [SeenDevice]? = nil
    var deviceCount: Int? = nil
    var activeDevices: Int? = nil
    var flagged: Bool? = nil        // 近 7 天 >1 台设备 → 爆红
    var id: String { account }
}

struct ActivityEvent: Codable, Identifiable, Hashable {
    let ts: Double
    let account: String
    let device: String
    let result: String
    var id: String { "\(ts)-\(account)-\(device)" }
    var allowed: Bool { result == "ok" }
}

struct AdminActivity: Codable {
    var events: [ActivityEvent]
    var accounts: [SeenAccount]
}

// GET / 自检
struct Health: Codable {
    var ok: Bool?
    var service: String?
    var ver: String?
    var signKey: String?
    var pub: String?
    var listSource: String?
    var allowCount: Int?
    var admin: String?
}

// GET /v1/admin/ping
struct AdminPing: Codable {
    var ok: Bool
    var admin: Bool
    var ver: String?
    var allowCount: Int?
    var recheckAfter: Int?
    var signKey: String?
}

struct AddAllowResult: Codable {
    var ok: Bool
    var added: Bool
    var entry: AllowEntry
}

struct SeedResult: Codable {
    var ok: Bool
    var added: Int
    var count: Int
}

// Cloudflare 聚合分析里的一个时间点。
struct AnalyticsPoint: Identifiable, Hashable {
    let date: Date
    let requests: Int
    let errors: Int
    var id: Date { date }
}

// 当天（UTC）额度用量。两部分各自可能失败，失败时对应 error 有值。
struct UsageToday {
    var workerRequests: Int?
    var workerError: String?
    var kv: [String: Int] = [:]   // read / write / delete / list
    var kvError: String?
}

struct AnalyticsSummary {
    var points: [AnalyticsPoint]
    var totalRequests: Int { points.reduce(0) { $0 + $1.requests } }
    var totalErrors: Int { points.reduce(0) { $0 + $1.errors } }
    var errorRate: Double { totalRequests == 0 ? 0 : Double(totalErrors) / Double(totalRequests) }
}
