import SwiftUI

// 统一视觉：液态玻璃取向——半透明卡片、克制的描边、柔和渐变背景。
enum Theme {
    static let accent   = Color(hex: 0x2E8BFF)
    static let accent2  = Color(hex: 0x32D6E6)
    static let good     = Color(hex: 0x34C759)
    static let warn     = Color(hex: 0xFF9F0A)
    static let bad      = Color(hex: 0xFF453A)
    static let mutedBad = Color(hex: 0xC94A42)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // 图表填充用的低透明度渐变（避免对 LinearGradient 直接 .opacity）。
    static var areaGradient: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.35), accent2.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }

    // 背景：系统分组底色上叠一层极淡的双色光晕。
    static func background() -> some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    Circle().fill(accent.opacity(0.14)).frame(width: geo.size.width * 0.9)
                        .blur(radius: 90).offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.22)
                    Circle().fill(accent2.opacity(0.12)).frame(width: geo.size.width * 0.8)
                        .blur(radius: 90).offset(x: geo.size.width * 0.35, y: geo.size.height * 0.28)
                }
            }.ignoresSafeArea()
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// 玻璃卡片容器：iOS 26 原生 Liquid Glass（在渐变背景上折射，自带高光与阴影）。
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func glassCard() -> some View { GlassCard { self } }
}

// 小标题。
struct SectionLabel: View {
    let text: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

// 状态胶囊。
struct StatusPill: View {
    enum Kind { case good, warn, bad, neutral }
    let text: String
    var kind: Kind = .neutral
    private var color: Color {
        switch kind { case .good: return Theme.good; case .warn: return Theme.warn
                      case .bad: return Theme.bad; case .neutral: return .secondary }
    }
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// 键值行。
struct KeyValueRow: View {
    let key: String
    let value: String
    var mono: Bool = false
    var valueColor: Color = .primary
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

// 大号指标。
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = Theme.accent
    var icon: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.title3).foregroundStyle(tint)
            }
            Text(value).font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.primary).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // 卡片本身已是玻璃，内层指标块用实心着色，避免「玻璃叠玻璃」。
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }
}

// 短哈希显示：前 10 + 省略 + 后 6。
func shortHash(_ h: String) -> String {
    guard h.count > 20 else { return h }
    return "\(h.prefix(10))…\(h.suffix(6))"
}

// 相对时间。
func relativeTime(_ unixSeconds: Double) -> String {
    guard unixSeconds > 0 else { return "—" }
    let date = Date(timeIntervalSince1970: unixSeconds)
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "zh_Hans")
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

func absoluteTime(_ unixSeconds: Double) -> String {
    guard unixSeconds > 0 else { return "—" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_Hans")
    f.dateFormat = "MM-dd HH:mm"
    return f.string(from: Date(timeIntervalSince1970: unixSeconds))
}
