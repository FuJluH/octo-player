import Foundation

/// A real-input FFT of a power-of-two size, done as a complex FFT of half the size. Only the
/// magnitudes of bins 0 to size / 2 are given.
final class RealFft {
    let size: Int
    private let half: Int
    private let re: UnsafeMutablePointer<Double>
    private let im: UnsafeMutablePointer<Double>
    private let cosHalf: UnsafeMutablePointer<Double>
    private let sinHalf: UnsafeMutablePointer<Double>
    private let cosFull: UnsafeMutablePointer<Double>
    private let sinFull: UnsafeMutablePointer<Double>
    private let reversed: UnsafeMutablePointer<Int>

    init(size: Int) {
        precondition(size >= 4 && size & (size - 1) == 0, "size must be a power of two")
        self.size = size
        let half = size / 2
        self.half = half
        re = .allocate(capacity: half)
        im = .allocate(capacity: half)
        re.initialize(repeating: 0, count: half)
        im.initialize(repeating: 0, count: half)
        cosHalf = .allocate(capacity: max(1, half / 2))
        sinHalf = .allocate(capacity: max(1, half / 2))
        for i in 0..<(half / 2) {
            cosHalf[i] = cos(2 * Double.pi * Double(i) / Double(half))
            sinHalf[i] = sin(2 * Double.pi * Double(i) / Double(half))
        }
        cosFull = .allocate(capacity: half + 1)
        sinFull = .allocate(capacity: half + 1)
        for i in 0...half {
            cosFull[i] = cos(2 * Double.pi * Double(i) / Double(size))
            sinFull[i] = sin(2 * Double.pi * Double(i) / Double(size))
        }
        reversed = .allocate(capacity: half)
        var bits = 0
        while 1 << bits < half { bits += 1 }
        for i in 0..<half {
            var r = 0
            for b in 0..<bits where (i >> b) & 1 == 1 { r |= 1 << (bits - 1 - b) }
            reversed[i] = r
        }
    }

    deinit {
        re.deallocate()
        im.deallocate()
        cosHalf.deallocate()
        sinHalf.deallocate()
        cosFull.deallocate()
        sinFull.deallocate()
        reversed.deallocate()
    }

    /// `out` gets |X[k]| for k = 0 ... size / 2.
    func magnitudes(_ input: [Double], _ out: inout [Double]) {
        input.withUnsafeBufferPointer { inBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                magnitudes(inBuf.baseAddress!, outBuf.baseAddress!)
            }
        }
    }

    func magnitudes(_ input: UnsafePointer<Double>, _ out: UnsafeMutablePointer<Double>) {
        let re = re, im = im, half = half
        for i in 0..<half {
            let j = reversed[i]
            re[j] = input[2 * i]
            im[j] = input[2 * i + 1]
        }
        var length = 2
        while length <= half {
            let step = half / length
            let mid = length / 2
            for j in 0..<mid {
                let wr = cosHalf[j * step]
                let wi = -sinHalf[j * step]
                var a = j
                while a < half {
                    let b = a + mid
                    let br = re[b], bi = im[b]
                    let tr = br * wr - bi * wi
                    let ti = br * wi + bi * wr
                    let ar = re[a], ai = im[a]
                    re[b] = ar - tr
                    im[b] = ai - ti
                    re[a] = ar + tr
                    im[a] = ai + ti
                    a += length
                }
            }
            length *= 2
        }
        for k in 0...half {
            let front = k == half ? 0 : k
            let back = k == 0 ? 0 : half - k
            let a = re[front], b = im[front], c = re[back], d = im[back]
            let evenRe = (a + c) / 2
            let evenIm = (b - d) / 2
            let oddRe = (b + d) / 2
            let oddIm = -(a - c) / 2
            let wr = cosFull[k], ws = sinFull[k]
            let xr = evenRe + wr * oddRe + ws * oddIm
            let xi = evenIm + wr * oddIm - ws * oddRe
            out[k] = (xr * xr + xi * xi).squareRoot()
        }
    }
}
