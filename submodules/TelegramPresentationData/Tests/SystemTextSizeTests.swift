import Foundation
import UIKit
import XCTest
import Display
import SwiftSignalKit

final class SystemTextSizeTests: XCTestCase {
    func testFontChangesAreDeliveredAndStopAfterDisposal() {
        let changed = self.expectation(description: "Initial font and changed font")
        changed.expectedFulfillmentCount = 2
        var received: [CGFloat] = []
        var expectedSize: CGFloat?
        let disposable = systemBodyFontSize().start(next: { size in
            received.append(size)
            changed.fulfill()
        })
        defer { disposable.dispose() }

        DispatchQueue.main.async {
            let currentSize = UIFont.preferredFont(forTextStyle: .body).pointSize
            let smallTraits = UITraitCollection(preferredContentSizeCategory: .extraSmall)
            let smallSize = UIFont.preferredFont(forTextStyle: .body, compatibleWith: smallTraits).pointSize
            let category: UIContentSizeCategory = currentSize == smallSize ? .accessibilityExtraExtraExtraLarge : .extraSmall
            expectedSize = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
            NotificationCenter.default.post(name: UIContentSizeCategory.didChangeNotification, object: nil, userInfo: [UIContentSizeCategory.newValueUserInfoKey: category.rawValue])
        }
        self.wait(for: [changed], timeout: 2.0)
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.last, expectedSize)

        disposable.dispose()
        let disposed = self.expectation(description: "Notification after disposal")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: UIContentSizeCategory.didChangeNotification, object: nil, userInfo: [UIContentSizeCategory.newValueUserInfoKey: UIContentSizeCategory.large.rawValue])
            disposed.fulfill()
        }
        self.wait(for: [disposed], timeout: 2.0)
        XCTAssertEqual(received.count, 2)
    }
}
