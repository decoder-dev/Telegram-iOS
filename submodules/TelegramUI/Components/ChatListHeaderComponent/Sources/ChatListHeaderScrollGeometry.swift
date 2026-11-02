import Foundation

struct ChatListHeaderScrollGeometry {
    let offset: CGFloat
    let largeTitleHeight: CGFloat
    let searchHeight: CGFloat

    var scrollHeight: CGFloat {
        return self.largeTitleHeight + self.searchHeight
    }

    var clippedOffset: CGFloat {
        return min(self.scrollHeight, self.offset)
    }

    var titleOffset: CGFloat {
        return min(self.largeTitleHeight, max(0.0, self.offset))
    }

    var searchOffset: CGFloat {
        return min(self.searchHeight, max(0.0, self.offset - self.largeTitleHeight))
    }

    var snappingOffset: CGFloat? {
        if self.offset > 0.0 && self.offset < self.largeTitleHeight {
            return self.offset < self.largeTitleHeight * 0.5 ? 0.0 : self.largeTitleHeight
        }
        if self.offset > self.largeTitleHeight && self.offset < self.scrollHeight {
            return self.searchOffset < self.searchHeight * 0.5 ? self.largeTitleHeight : self.scrollHeight
        }
        return nil
    }

    var titleFraction: CGFloat {
        guard self.largeTitleHeight > 0.0 else {
            return 0.0
        }
        return 1.0 - self.titleOffset / self.largeTitleHeight
    }

    var searchFraction: CGFloat {
        guard self.searchHeight > 0.0 else {
            return 1.0
        }
        return 1.0 - self.searchOffset / self.searchHeight
    }
}
