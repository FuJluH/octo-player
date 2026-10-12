import Foundation

/// SHA-1 and SHA-256, for names and checks (not for secrets): the same on every platform, with
/// no system library needed.
public enum Hashes {
    public static func sha1(_ data: some Collection<UInt8>) -> [UInt8] {
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        for block in blocks(Array(data)) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 { w[i] = word(block, i) }
            for i in 16..<80 { w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for i in 0..<80 {
                let (f, k): (UInt32, UInt32) = switch i {
                case 0..<20: ((b & c) | (~b & d), 0x5A82_7999)
                case 20..<40: (b ^ c ^ d, 0x6ED9_EBA1)
                case 40..<60: ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
                default: (b ^ c ^ d, 0xCA62_C1D6)
                }
                let t = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotl(b, 30)
                b = a
                a = t
            }
            h[0] &+= a
            h[1] &+= b
            h[2] &+= c
            h[3] &+= d
            h[4] &+= e
        }
        return h.flatMap(bytes)
    }

    public static func sha256(_ data: some Collection<UInt8>) -> [UInt8] {
        var h: [UInt32] = [0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A, 0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19]
        for block in blocks(Array(data)) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { w[i] = word(block, i) }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k256[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g
                g = f
                f = e
                e = d &+ t1
                d = c
                c = b
                b = a
                a = t1 &+ t2
            }
            h[0] &+= a
            h[1] &+= b
            h[2] &+= c
            h[3] &+= d
            h[4] &+= e
            h[5] &+= f
            h[6] &+= g
            h[7] &+= hh
        }
        return h.flatMap(bytes)
    }

    public static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func sha1Hex(_ text: String) -> String { hex(sha1(Array(text.utf8))) }
    public static func sha256Hex(_ data: some Collection<UInt8>) -> String { hex(sha256(data)) }

    /// The message padded and cut into 64-byte blocks.
    private static func blocks(_ message: [UInt8]) -> [ArraySlice<UInt8>] {
        var padded = message
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        let bits = UInt64(message.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) { padded.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        return stride(from: 0, to: padded.count, by: 64).map { padded[$0..<$0 + 64] }
    }

    private static func word(_ block: ArraySlice<UInt8>, _ i: Int) -> UInt32 {
        let base = block.startIndex + i * 4
        return UInt32(block[base]) << 24 | UInt32(block[base + 1]) << 16 | UInt32(block[base + 2]) << 8 | UInt32(block[base + 3])
    }

    private static func bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private static let k256: [UInt32] = [
        0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
        0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
        0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
        0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
        0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
        0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
        0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
        0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
    ]
}

/// The pictures a server sends in place of a cover it cannot give, told apart by their length
/// and digest. Navidrome answers with its blue record when it has no picture: a 200 like any
/// cover, so only its bytes tell it apart.
public struct StandIns: Sendable {
    private let known: [Int: Set<String>]
    /// The longest stand-in, so a reader knows how far to look.
    public let longest: Int

    public init(_ known: [Int: Set<String>]) {
        self.known = known
        longest = known.keys.max() ?? 0
    }

    /// Whether a picture this many bytes long could be a stand-in at all.
    public func mayBe(_ length: Int64) -> Bool {
        length >= 1 && length <= Int64(longest) && known[Int(length)] != nil
    }

    public func isStandIn(_ bytes: some Collection<UInt8>) -> Bool {
        guard let digests = known[bytes.count] else { return false }
        return digests.contains(Hashes.sha256Hex(bytes))
    }
}

/// The stand-ins servers are known to send.
public let standInCovers = StandIns([
    // Navidrome's album-placeholder.webp, 1024 by 1024, as Navidrome sent it in October 2026.
    69_228: ["273a4dbd61dfbb0a12d5d8ffe780eb7a3d4d000bc9771c5411cc70ae4dfa8a1f"],
])
