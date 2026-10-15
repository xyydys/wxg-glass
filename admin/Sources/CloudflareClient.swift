import Foundation

// Cloudflare GraphQL Analytics：抓 worker `xyylwc` 的请求量 / 错误量时间序列。
// 需要一个 API Token，权限：Account Analytics → Read（范围选对应账号即可）。
// 创建：Cloudflare 控制台 → My Profile → API Tokens → Create Token → Custom。
struct CloudflareClient {
    let token: String
    let accountId: String
    var scriptName = "xyylwc"

    private static let endpoint = "https://api.cloudflare.com/client/v4/graphql"

    enum Window: String, CaseIterable, Identifiable {
        case day = "24 小时", week = "7 天"
        var id: String { rawValue }
        var hours: Int { self == .day ? 24 : 24 * 7 }
    }

    func fetch(window: Window) async throws -> AnalyticsSummary {
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -window.hours, to: now)!
        let iso = ISO8601DateFormatter()
        let dimField = "datetimeHour"   // 统一按小时分桶：24h=24 点、7d=168 点，图表都扛得住

        let query = """
        query($a:String!,$s:Time!,$u:Time!,$script:String!){
          viewer{
            accounts(filter:{accountTag:$a}){
              workersInvocationsAdaptiveGroups(
                limit:10000,
                filter:{datetime_geq:$s, datetime_leq:$u, scriptName:$script},
                orderBy:[\(dimField)_ASC]
              ){
                dimensions{ \(dimField) }
                sum{ requests errors }
              }
            }
          }
        }
        """
        let variables: [String: Any] = [
            "a": accountId,
            "s": iso.string(from: start),
            "u": iso.string(from: now),
            "script": scriptName,
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
            .first?["workersInvocationsAdaptiveGroups"] as? [[String: Any]] ?? []

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parserPlain = ISO8601DateFormatter()

        var points: [AnalyticsPoint] = []
        for g in groups {
            let dims = g["dimensions"] as? [String: Any]
            let sum = g["sum"] as? [String: Any]
            let raw = (dims?[dimField] as? String) ?? ""
            let date = parser.date(from: raw) ?? parserPlain.date(from: raw)
                ?? parserPlain.date(from: raw + "T00:00:00Z") ?? Date()
            let requests = (sum?["requests"] as? Int) ?? Int((sum?["requests"] as? Double) ?? 0)
            let errors = (sum?["errors"] as? Int) ?? Int((sum?["errors"] as? Double) ?? 0)
            points.append(AnalyticsPoint(date: date, requests: requests, errors: errors))
        }
        points.sort { $0.date < $1.date }
        return AnalyticsSummary(points: points)
    }
}
