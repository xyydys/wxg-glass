import Foundation

// Cloudflare GraphQL Analytics：抓 worker `xyylwc` 的请求量 / 错误量时间序列，以及当天额度用量。
// 需要一个 API Token，权限：Account → Account Analytics → Read（范围选对应账号即可）。
// 请求曲线用官方教程「Querying Workers Metrics with GraphQL」里的 workersInvocationsAdaptive
// （没有 …Groups 后缀，变量照官方示例用小写 string）；KV 用量用官方 KV 文档里的 kvOperationsAdaptiveGroups。
struct CloudflareClient {
    let token: String
    let accountId: String
    var scriptName = "xyylwc"

    private static let endpoint = "https://api.cloudflare.com/client/v4/graphql"
    private static let hour: Double = 3600

    enum Window: String, CaseIterable, Identifiable {
        case day = "24 小时", week = "7 天"
        var id: String { rawValue }
        var hours: Int { self == .day ? 24 : 24 * 7 }
    }

    private struct Row { let date: Date; let requests: Int; let errors: Int }

    // MARK: 请求曲线

    func fetch(window: Window) async throws -> AnalyticsSummary {
        let now = Date()
        let start = now.addingTimeInterval(-Double(window.hours) * Self.hour)

        // 先按小时分组（行数少）；该数据集若没有 datetimeHour 维度，退回官方示例里的 datetime，本地按小时汇总。
        let rows: [Row]
        do { rows = try await series(dimension: "datetimeHour", start: start, end: now) }
        catch let e as APIError where e.message.contains("datetimeHour") {
            rows = try await series(dimension: "datetime", start: start, end: now)
        }

        // 按小时分桶，窗口内每个小时都补上（没请求的小时为 0，曲线不会跨空档连线）。
        let first = floor(start.timeIntervalSince1970 / Self.hour) * Self.hour
        let last = floor(now.timeIntervalSince1970 / Self.hour) * Self.hour
        var buckets: [Double: (requests: Int, errors: Int)] = [:]
        for t in stride(from: first, through: last, by: Self.hour) { buckets[t] = (0, 0) }
        for r in rows {
            let k = floor(r.date.timeIntervalSince1970 / Self.hour) * Self.hour
            let cur = buckets[k] ?? (0, 0)
            buckets[k] = (cur.requests + r.requests, cur.errors + r.errors)
        }
        let points = buckets
            .map { AnalyticsPoint(date: Date(timeIntervalSince1970: $0.key), requests: $0.value.requests, errors: $0.value.errors) }
            .sorted { $0.date < $1.date }
        return AnalyticsSummary(points: points)
    }

    private func series(dimension: String, start: Date, end: Date) async throws -> [Row] {
        let query = """
        query GetWorkersAnalytics($accountTag: string, $datetimeStart: string, $datetimeEnd: string, $scriptName: string) {
          viewer {
            accounts(filter: {accountTag: $accountTag}) {
              workersInvocationsAdaptive(limit: 10000, filter: {
                scriptName: $scriptName,
                datetime_geq: $datetimeStart,
                datetime_leq: $datetimeEnd
              }) {
                sum { requests errors }
                dimensions { \(dimension) }
              }
            }
          }
        }
        """
        let account = try await post(query, [
            "accountTag": accountId,
            "datetimeStart": Self.iso(start),
            "datetimeEnd": Self.iso(end),
            "scriptName": scriptName,
        ])
        let groups = account["workersInvocationsAdaptive"] as? [[String: Any]] ?? []

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        return groups.compactMap { g in
            let raw = ((g["dimensions"] as? [String: Any])?[dimension] as? String) ?? ""
            guard let date = plain.date(from: raw) ?? withFraction.date(from: raw) else { return nil }
            let sum = g["sum"] as? [String: Any]
            return Row(date: date, requests: Self.int(sum?["requests"]), errors: Self.int(sum?["errors"]))
        }
    }

    // MARK: 今日额度

    // 免费版每天额度按 UTC 0 点重置、全账号合计。两部分分开查：一边出错另一边照常显示。
    func usageToday() async -> UsageToday {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let midnight = utc.startOfDay(for: now)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = utc
        dayFormatter.timeZone = utc.timeZone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: now)

        async let workers = workerRequests(since: midnight, until: now)
        async let kv = kvOperations(day: day)

        var usage = UsageToday()
        do { usage.workerRequests = try await workers } catch { usage.workerError = Self.message(error) }
        do { usage.kv = try await kv } catch { usage.kvError = Self.message(error) }
        return usage
    }

    // 当天全账号 Worker 请求数（不限脚本，免费额度是全账号合计）。
    private func workerRequests(since: Date, until: Date) async throws -> Int {
        let query = """
        query GetWorkersUsage($accountTag: string, $datetimeStart: string, $datetimeEnd: string) {
          viewer {
            accounts(filter: {accountTag: $accountTag}) {
              workersInvocationsAdaptive(limit: 10000, filter: {
                datetime_geq: $datetimeStart,
                datetime_leq: $datetimeEnd
              }) {
                sum { requests }
                dimensions { scriptName }
              }
            }
          }
        }
        """
        let account = try await post(query, [
            "accountTag": accountId,
            "datetimeStart": Self.iso(since),
            "datetimeEnd": Self.iso(until),
        ])
        let rows = account["workersInvocationsAdaptive"] as? [[String: Any]] ?? []
        return rows.reduce(0) { $0 + Self.int(($1["sum"] as? [String: Any])?["requests"]) }
    }

    // 当天全账号 KV 操作数，按 actionType（read / write / delete / list）分。
    private func kvOperations(day: String) async throws -> [String: Int] {
        // day 是本地生成的 yyyy-MM-dd，直接写进查询，免得日期变量类型对不上。
        let query = """
        query GetKVUsage($accountTag: string) {
          viewer {
            accounts(filter: {accountTag: $accountTag}) {
              kvOperationsAdaptiveGroups(limit: 10000, filter: { date_geq: "\(day)", date_leq: "\(day)" }) {
                sum { requests }
                dimensions { actionType }
              }
            }
          }
        }
        """
        let account = try await post(query, ["accountTag": accountId])
        let rows = account["kvOperationsAdaptiveGroups"] as? [[String: Any]] ?? []
        var out: [String: Int] = [:]
        for r in rows {
            let type = (((r["dimensions"] as? [String: Any])?["actionType"] as? String) ?? "其他").lowercased()
            out[type, default: 0] += Self.int((r["sum"] as? [String: Any])?["requests"])
        }
        return out
    }

    // MARK: 公用

    // 发一条 GraphQL，返回 data.viewer.accounts[0]；出错抛 APIError（带 Cloudflare 原话）。
    private func post(_ query: String, _ variables: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: Self.endpoint) else { throw APIError(message: "端点无效") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw APIError(message: "网络错误：\(error.localizedDescription)") }
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "无响应") }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(message: "返回解析失败（HTTP \(http.statusCode)）")
        }
        if let errs = root["errors"] as? [[String: Any]], let first = errs.first {
            throw APIError(message: "Cloudflare：" + ((first["message"] as? String) ?? "GraphQL 错误"))
        }
        guard http.statusCode == 200 else { throw APIError(message: "HTTP \(http.statusCode)（Token 权限需含 Account Analytics:Read）") }
        return (((root["data"] as? [String: Any])?["viewer"] as? [String: Any])?["accounts"] as? [[String: Any]])?.first ?? [:]
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func int(_ value: Any?) -> Int { (value as? Int) ?? Int((value as? Double) ?? 0) }
    private static func message(_ error: Error) -> String { (error as? APIError)?.message ?? error.localizedDescription }
}
