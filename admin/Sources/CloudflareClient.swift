import Foundation

// Cloudflare GraphQL Analytics：抓 worker `xyylwc` 的请求量 / 错误量时间序列。
// 需要一个 API Token，权限：Account → Account Analytics → Read（范围选对应账号即可）。
// 数据集是官方教程「Querying Workers Metrics with GraphQL」里的 workersInvocationsAdaptive
// （没有 …Groups 后缀）；变量类型照官方示例用小写 string。
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

    func fetch(window: Window) async throws -> AnalyticsSummary {
        let now = Date()
        let start = now.addingTimeInterval(-Double(window.hours) * Self.hour)

        // 先按小时分组（行数少）；该数据集若没有 datetimeHour 维度，退回官方示例里的 datetime，本地按小时汇总。
        let rows: [Row]
        do { rows = try await query(dimension: "datetimeHour", start: start, end: now) }
        catch let e as APIError where e.message.contains("datetimeHour") {
            rows = try await query(dimension: "datetime", start: start, end: now)
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

    private func query(dimension: String, start: Date, end: Date) async throws -> [Row] {
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
        let iso = ISO8601DateFormatter()
        let variables: [String: Any] = [
            "accountTag": accountId,
            "datetimeStart": iso.string(from: start),
            "datetimeEnd": iso.string(from: end),
            "scriptName": scriptName,
        ]

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

        let groups = (((root["data"] as? [String: Any])?["viewer"] as? [String: Any])?["accounts"] as? [[String: Any]])?
            .first?["workersInvocationsAdaptive"] as? [[String: Any]] ?? []

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        return groups.compactMap { g in
            let raw = ((g["dimensions"] as? [String: Any])?[dimension] as? String) ?? ""
            guard let date = plain.date(from: raw) ?? withFraction.date(from: raw) else { return nil }
            let sum = g["sum"] as? [String: Any]
            let requests = (sum?["requests"] as? Int) ?? Int((sum?["requests"] as? Double) ?? 0)
            let errors = (sum?["errors"] as? Int) ?? Int((sum?["errors"] as? Double) ?? 0)
            return Row(date: date, requests: requests, errors: errors)
        }
    }
}
