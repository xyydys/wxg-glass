import Foundation
import CryptoKit

// 和插件(WXGLicense.m / WXGUnlock.m)、worker 完全一致的账号派生：
//   account = SHA-256("WXGLiquidGlass.license.v1:" + wxid) 的小写十六进制。
// 所以这里输 wxid 就能算出名单里要填的那串 64 位哈希。
enum WXGCrypto {
    static let licensePrefix = "WXGLiquidGlass.license.v1:"

    static func accountHash(forWXID wxid: String) -> String {
        let input = (licensePrefix + wxid).data(using: .utf8) ?? Data()
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    static func isAccountHash(_ s: String) -> Bool {
        let t = s.lowercased()
        return t.count == 64 && t.allSatisfy { $0.isHexDigit }
    }
}
