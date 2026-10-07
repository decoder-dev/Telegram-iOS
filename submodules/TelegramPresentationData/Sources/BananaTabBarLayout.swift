import Foundation
import SwiftSignalKit

public struct BananaTabBarLayout: Equatable {
    public static let didChangeNotification = Notification.Name("BananaTabBarLayout.didChange")
    private static let state = Atomic<BananaTabBarLayout>(value: BananaTabBarLayout(hidden: false, contacts: true, calls: true, wide: false, integratedSearch: false, searchOnLeft: false))
    public static var current: BananaTabBarLayout {
        get { state.with { $0 } }
        set {
            let previous = state.swap(newValue)
            if previous != newValue { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        }
    }
    public let hidden: Bool
    public let contacts: Bool
    public let calls: Bool
    public let wide: Bool
    public let integratedSearch: Bool
    public let searchOnLeft: Bool

    public init(hidden: Bool, contacts: Bool, calls: Bool, wide: Bool, integratedSearch: Bool, searchOnLeft: Bool) {
        self.hidden = hidden
        self.contacts = contacts
        self.calls = calls
        self.wide = wide
        self.integratedSearch = integratedSearch
        self.searchOnLeft = searchOnLeft
    }
}

