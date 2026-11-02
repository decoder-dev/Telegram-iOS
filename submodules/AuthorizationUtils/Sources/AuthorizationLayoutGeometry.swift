import Foundation

public struct AuthorizationLayoutItemSpacing {
    public var weight: CGFloat
    public var maxValue: CGFloat

    public init(weight: CGFloat, maxValue: CGFloat) {
        self.weight = weight
        self.maxValue = maxValue
    }
}

func authorizationLayoutFrames(bounds: CGRect, sizes: [CGSize], spacings: [AuthorizationLayoutItemSpacing], failIfDoesNotFit: Bool) -> [CGRect]? {
    precondition(spacings.count == sizes.count * 2)
    let fixedHeight = sizes.reduce(CGFloat(0.0)) { $0 + $1.height }
    if failIfDoesNotFit && fixedHeight > bounds.height {
        return nil
    }

    var remainingHeight = max(0.0, bounds.height - fixedHeight)
    var values = Array(repeating: CGFloat(0.0), count: spacings.count)
    var pending = spacings.indices.filter { spacings[$0].weight > 0.0 && spacings[$0].maxValue > 0.0 }
    while !pending.isEmpty {
        let totalWeight = pending.reduce(CGFloat(0.0)) { $0 + spacings[$1].weight }
        let capped = pending.filter { remainingHeight * spacings[$0].weight / totalWeight >= spacings[$0].maxValue }
        if capped.isEmpty {
            for index in pending {
                values[index] = floor(remainingHeight * spacings[index].weight / totalWeight)
            }
            break
        }
        for index in capped {
            values[index] = spacings[index].maxValue
            remainingHeight = max(0.0, remainingHeight - values[index])
        }
        pending.removeAll { capped.contains($0) }
    }

    let height = fixedHeight + values.reduce(0.0, +)
    var y = bounds.minY + floor((bounds.height - height) / 2.0)
    var frames: [CGRect] = []
    frames.reserveCapacity(sizes.count)
    for (index, size) in sizes.enumerated() {
        y += values[index * 2]
        frames.append(CGRect(x: bounds.minX + floor((bounds.width - size.width) / 2.0), y: y, width: size.width, height: size.height))
        y += size.height + values[index * 2 + 1]
    }
    return frames
}
