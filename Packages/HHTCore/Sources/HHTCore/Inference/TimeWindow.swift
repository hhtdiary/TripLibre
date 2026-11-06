import Foundation

extension RandomAccessCollection where Element == RawPoint {
    /// First index whose timestamp is `> t` (or `>= t` when `inclusive`). Requires ascending timestamps.
    func partitionIndex(after t: Date, inclusive: Bool) -> Index {
        var lo = startIndex, n = count
        while n > 0 {
            let half = n / 2
            let mid = index(lo, offsetBy: half)
            let ts = self[mid].timestamp
            if inclusive ? ts < t : ts <= t {
                lo = index(after: mid)
                n -= half + 1
            } else {
                n = half
            }
        }
        return lo
    }

    /// The points strictly inside `(from, to)`, in their original order, found by binary search.
    ///
    /// Equivalent to `filter { $0.timestamp > from && $0.timestamp < to }` on a collection sorted by
    /// timestamp (e.g. the output of `StayDetector.clean`), without scanning or copying the whole array.
    func strictlyBetween(_ from: Date, _ to: Date) -> SubSequence {
        let lo = partitionIndex(after: from, inclusive: false)   // first ts > from
        let hi = partitionIndex(after: to, inclusive: true)      // first ts >= to
        return lo < hi ? self[lo..<hi] : self[lo..<lo]
    }
}
