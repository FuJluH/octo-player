import Foundation

/// XChaCha20-Poly1305 (the extended-nonce ChaCha20-Poly1305 AEAD), written out so OctoKit has
/// no dependencies and builds the same on iOS and Linux. A 32 byte key, a 24 byte nonce, and a
/// 16 byte tag after the ciphertext.
enum XChaCha20Poly1305 {
    enum Failure: Error { case badKey, badNonce, tagMismatch }

    static func seal(_ plain: [UInt8], key: [UInt8], nonce: [UInt8], aad: [UInt8]) throws -> [UInt8] {
        let (subkey, inner) = try derive(key: key, nonce: nonce)
        let polyKey = Array(ChaCha20.block(key: subkey, counter: 0, nonce: inner).prefix(32))
        let cipher = ChaCha20.xor(plain, key: subkey, counter: 1, nonce: inner)
        return cipher + Poly1305.tag(message: macData(aad: aad, cipher: cipher), key: polyKey)
    }

    static func open(_ sealed: [UInt8], key: [UInt8], nonce: [UInt8], aad: [UInt8]) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw Failure.tagMismatch }
        let (subkey, inner) = try derive(key: key, nonce: nonce)
        let cipher = Array(sealed.dropLast(16))
        let tag = Array(sealed.suffix(16))
        let polyKey = Array(ChaCha20.block(key: subkey, counter: 0, nonce: inner).prefix(32))
        let expected = Poly1305.tag(message: macData(aad: aad, cipher: cipher), key: polyKey)
        var difference: UInt8 = 0
        for i in 0..<16 { difference |= expected[i] ^ tag[i] }
        guard difference == 0 else { throw Failure.tagMismatch }
        return ChaCha20.xor(cipher, key: subkey, counter: 1, nonce: inner)
    }

    /// HChaCha20 makes a subkey from the key and the nonce's first 16 bytes; the inner 12 byte
    /// nonce is four zero bytes and the nonce's last 8.
    private static func derive(key: [UInt8], nonce: [UInt8]) throws -> ([UInt8], [UInt8]) {
        guard key.count == 32 else { throw Failure.badKey }
        guard nonce.count == 24 else { throw Failure.badNonce }
        return (ChaCha20.hChaCha(key: key, nonce: Array(nonce.prefix(16))), [0, 0, 0, 0] + Array(nonce.suffix(8)))
    }

    private static func macData(aad: [UInt8], cipher: [UInt8]) -> [UInt8] {
        func pad(_ count: Int) -> [UInt8] { [UInt8](repeating: 0, count: (16 - count % 16) % 16) }
        func le64(_ n: Int) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: UInt64(n) >> (8 * UInt64($0))) } }
        return aad + pad(aad.count) + cipher + pad(cipher.count) + le64(aad.count) + le64(cipher.count)
    }
}

enum ChaCha20 {
    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }

    private static func quarter(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] = rotl(s[d] ^ s[a], 16)
        s[c] = s[c] &+ s[d]; s[b] = rotl(s[b] ^ s[c], 12)
        s[a] = s[a] &+ s[b]; s[d] = rotl(s[d] ^ s[a], 8)
        s[c] = s[c] &+ s[d]; s[b] = rotl(s[b] ^ s[c], 7)
    }

    private static func words(_ bytes: [UInt8]) -> [UInt32] {
        stride(from: 0, to: bytes.count, by: 4).map {
            UInt32(bytes[$0]) | UInt32(bytes[$0 + 1]) << 8 | UInt32(bytes[$0 + 2]) << 16 | UInt32(bytes[$0 + 3]) << 24
        }
    }

    private static func rounds(_ state: inout [UInt32]) {
        for _ in 0..<10 {
            quarter(&state, 0, 4, 8, 12); quarter(&state, 1, 5, 9, 13); quarter(&state, 2, 6, 10, 14); quarter(&state, 3, 7, 11, 15)
            quarter(&state, 0, 5, 10, 15); quarter(&state, 1, 6, 11, 12); quarter(&state, 2, 7, 8, 13); quarter(&state, 3, 4, 9, 14)
        }
    }

    private static let constants: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]

    static func block(key: [UInt8], counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        let initial = constants + words(key) + [counter] + words(nonce)
        var state = initial
        rounds(&state)
        return (0..<16).flatMap { i -> [UInt8] in
            let word = state[i] &+ initial[i]
            return [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 24)]
        }
    }

    static func hChaCha(key: [UInt8], nonce: [UInt8]) -> [UInt8] {
        var state = constants + words(key) + words(nonce)
        rounds(&state)
        return ([0, 1, 2, 3, 12, 13, 14, 15] as [Int]).flatMap { i -> [UInt8] in
            let word = state[i]
            return [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 24)]
        }
    }

    static func xor(_ input: [UInt8], key: [UInt8], counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: input.count)
        var blockCounter = counter
        var offset = 0
        while offset < input.count {
            let stream = block(key: key, counter: blockCounter, nonce: nonce)
            let count = min(64, input.count - offset)
            for i in 0..<count { out[offset + i] = input[offset + i] ^ stream[i] }
            offset += 64
            blockCounter &+= 1
        }
        return out
    }
}

/// Poly1305 with 26 bit limbs.
enum Poly1305 {
    static func tag(message: [UInt8], key: [UInt8]) -> [UInt8] {
        func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
        let r0 = UInt64(le32(key, 0) & 0x3ff_ffff)
        let r1 = UInt64((le32(key, 3) >> 2) & 0x3ff_ff03)
        let r2 = UInt64((le32(key, 6) >> 4) & 0x3ff_c0ff)
        let r3 = UInt64((le32(key, 9) >> 6) & 0x3f0_3fff)
        let r4 = UInt64((le32(key, 12) >> 8) & 0x00f_ffff)
        let s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5
        var h0: UInt64 = 0, h1: UInt64 = 0, h2: UInt64 = 0, h3: UInt64 = 0, h4: UInt64 = 0

        var offset = 0
        while offset < message.count {
            var block = [UInt8](repeating: 0, count: 17)
            let count = min(16, message.count - offset)
            for i in 0..<count { block[i] = message[offset + i] }
            // The block as a 130 bit number: its bytes, then a 1 byte (the 17th byte for a whole block).
            block[count] = 1
            let t0 = UInt64(le32(block, 0)), t1 = UInt64(le32(block, 4)), t2 = UInt64(le32(block, 8)), t3 = UInt64(le32(block, 12))
            h0 += t0 & 0x3ff_ffff
            h1 += ((t0 >> 26) | (t1 << 6)) & 0x3ff_ffff
            h2 += ((t1 >> 20) | (t2 << 12)) & 0x3ff_ffff
            h3 += ((t2 >> 14) | (t3 << 18)) & 0x3ff_ffff
            h4 += (t3 >> 8) | (UInt64(block[16]) << 24)

            let d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
            var d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
            var d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
            var d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
            var d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0
            var c = d0 >> 26; h0 = d0 & 0x3ff_ffff
            d1 += c; c = d1 >> 26; h1 = d1 & 0x3ff_ffff
            d2 += c; c = d2 >> 26; h2 = d2 & 0x3ff_ffff
            d3 += c; c = d3 >> 26; h3 = d3 & 0x3ff_ffff
            d4 += c; c = d4 >> 26; h4 = d4 & 0x3ff_ffff
            h0 += c * 5; c = h0 >> 26; h0 &= 0x3ff_ffff
            h1 += c
            offset += 16
        }

        var c = h1 >> 26; h1 &= 0x3ff_ffff
        h2 += c; c = h2 >> 26; h2 &= 0x3ff_ffff
        h3 += c; c = h3 >> 26; h3 &= 0x3ff_ffff
        h4 += c; c = h4 >> 26; h4 &= 0x3ff_ffff
        h0 += c * 5; c = h0 >> 26; h0 &= 0x3ff_ffff
        h1 += c

        var g0 = h0 &+ 5; c = g0 >> 26; g0 &= 0x3ff_ffff
        var g1 = h1 &+ c; c = g1 >> 26; g1 &= 0x3ff_ffff
        var g2 = h2 &+ c; c = g2 >> 26; g2 &= 0x3ff_ffff
        var g3 = h3 &+ c; c = g3 >> 26; g3 &= 0x3ff_ffff
        let g4 = h4 &+ c &- (1 << 26)
        // When g4 did not go below zero, h is at least p, and g is h minus p.
        let useG = (g4 >> 63) == 0
        if useG { h0 = g0; h1 = g1; h2 = g2; h3 = g3; h4 = g4 & 0x3ff_ffff }

        let f0 = (h0 | (h1 << 26)) & 0xffff_ffff
        let f1 = ((h1 >> 6) | (h2 << 20)) & 0xffff_ffff
        let f2 = ((h2 >> 12) | (h3 << 14)) & 0xffff_ffff
        let f3 = ((h3 >> 18) | (h4 << 8)) & 0xffff_ffff
        var out = f0 + UInt64(le32(key, 16)); let w0 = UInt32(truncatingIfNeeded: out)
        out = f1 + UInt64(le32(key, 20)) + (out >> 32); let w1 = UInt32(truncatingIfNeeded: out)
        out = f2 + UInt64(le32(key, 24)) + (out >> 32); let w2 = UInt32(truncatingIfNeeded: out)
        out = f3 + UInt64(le32(key, 28)) + (out >> 32); let w3 = UInt32(truncatingIfNeeded: out)
        return [w0, w1, w2, w3].flatMap { word in
            [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 24)]
        }
    }
}
