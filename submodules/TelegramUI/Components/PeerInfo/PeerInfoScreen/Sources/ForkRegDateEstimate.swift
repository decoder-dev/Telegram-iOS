import Foundation

/// Fork (Ghostgram): when an account was most likely created, estimated from its user ID alone with the anchor table
/// (`ForkRegDateAnchors`). Nothing leaves the device. Used only where Telegram itself did not say
/// (`PeerStatusSettings.registrationDate`).
enum ForkRegDateEstimate {
    struct Result: Equatable {
        /// Unix seconds, UTC.
        let point: Int64
        let from: Int64
        let to: Int64

        /// A 90% band up to half a year wide is shown as a month; a wider one as a year.
        var isMonthPrecise: Bool {
            return self.to - self.from <= 183 * 86400
        }
    }

    static func estimate(userId: Int64, now: Int64 = Int64(Date().timeIntervalSince1970)) -> Result? {
        guard let raw = self.rawEstimate(userId: userId, now: max(now, ForkRegDateAnchors.dataEnd)) else {
            return nil
        }
        return Result(point: raw.point, from: raw.from, to: raw.to)
    }

    /// "≈ March 2016" or "≈ 2016", in the app's language.
    static func text(_ result: Result, russian: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: russian ? "ru_RU" : "en_US")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = result.isMonthPrecise ? "LLLL yyyy" : "yyyy"
        return "≈ " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(result.point)))
    }

    static func isReserved(_ userId: Int64) -> Bool {
        switch userId {
        case 777000, 333000, 489000, 4244000:
            return true
        default:
            return false
        }
    }

    /// The table alone: (point, from, to). nil for IDs that are not accounts on the counter.
    static func rawEstimate(userId: Int64, now: Int64) -> (point: Int64, from: Int64, to: Int64)? {
        guard userId > 0, !self.isReserved(userId) else {
            return nil
        }
        let ids = ForkRegDateAnchors.ids
        let points = ForkRegDateAnchors.points
        let lows = ForkRegDateAnchors.lows
        let highs = ForkRegDateAnchors.highs
        let count = ids.count
        guard count >= 2, points.count == count, lows.count == count, highs.count == count else {
            return nil
        }
        let last = count - 1
        if userId >= ids[last] {
            // Newer than every anchor: the point follows the last year's ID growth, the low edge moves at most as fast
            // as IDs could have grown, and the range never ends after now.
            let lastPoint = Int64(points[last])
            let lastLow = Int64(lows[last])
            let band = Int64(highs[last]) - lastLow
            let offset = Double(userId - ids[last])
            let upper = max(lastPoint, now)
            let point = self.clamp(Double(lastPoint) + offset / ForkRegDateAnchors.idsPerSecond, lower: lastPoint, upper: upper)
            let lowCap = min(point, max(upper - band, lastLow))
            let from = self.clamp(Double(lastLow) + offset / (ForkRegDateAnchors.idsPerSecond * ForkRegDateAnchors.maxRateFactor), lower: lastLow, upper: max(lastLow, lowCap))
            return (point, max(ForkRegDateAnchors.launch, from), upper)
        }
        // First index with ids[i] > userId; the table starts at ID 0, so i >= 1.
        var low = 0
        var high = last
        while low < high {
            let mid = (low + high) / 2
            if ids[mid] <= userId {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let i = low
        if i == 0 {
            let to = min(Int64(highs[0]), now)
            let point = min(Int64(points[0]), to)
            return (point, max(ForkRegDateAnchors.launch, min(Int64(lows[0]), point)), to)
        }
        let fraction = Double(userId - ids[i - 1]) / Double(ids[i] - ids[i - 1])
        var to = self.interpolate(highs[i - 1], highs[i], fraction)
        var point = self.interpolate(points[i - 1], points[i], fraction)
        var from = self.interpolate(lows[i - 1], lows[i], fraction)
        // Near the top of the table accounts made after the data still get IDs: once the data is old, the high edge
        // there moves on with the clock.
        let distance = Double(ids[last] - userId)
        if distance < ForkRegDateAnchors.frontSpan && now > ForkRegDateAnchors.dataEnd {
            let shift = Double(now - ForkRegDateAnchors.dataEnd) * (1.0 - distance / ForkRegDateAnchors.frontSpan)
            to += Int64(shift.rounded())
        }
        to = min(to, now)
        point = min(point, to)
        from = max(ForkRegDateAnchors.launch, min(from, point))
        return (point, from, to)
    }

    static func interpolate(_ a: Int32, _ b: Int32, _ fraction: Double) -> Int64 {
        let value = Double(a) + (Double(b) - Double(a)) * fraction
        return Int64(value.rounded())
    }

    static func clamp(_ value: Double, lower: Int64, upper: Int64) -> Int64 {
        if !(value > Double(lower)) {
            return lower
        }
        if value >= Double(upper) {
            return upper
        }
        return Int64(value.rounded())
    }
}
