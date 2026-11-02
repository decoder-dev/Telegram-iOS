import Foundation
import UIKit
import XCTest
import ButtonComponent
import ComponentFlow
import Display

final class ButtonAccessibilityTests: XCTestCase {
    func testAdaptiveHeightFitsTextAndKeepsTheConfiguredMinimum() {
        let host = ComponentView<Empty>()
        func update(fontSize: CGFloat, adaptive: Bool) -> CGSize {
            return host.update(
                transition: .immediate,
                component: AnyComponent(ButtonComponent(
                    background: .init(color: .blue, foreground: .white, pressedColor: .blue, cornerRadius: 26.0),
                    content: AnyComponentWithIdentity(id: 0, component: AnyComponent(Text(text: "Продолжить", font: Font.semibold(fontSize), color: .white))),
                    contentInsets: UIEdgeInsets(top: 12.0, left: 13.0, bottom: 12.0, right: 13.0),
                    fitToContentHeight: adaptive,
                    action: {}
                )),
                environment: {},
                containerSize: CGSize(width: 300.0, height: 52.0)
            )
        }
        XCTAssertEqual(update(fontSize: 17.0, adaptive: true).height, 52.0)
        XCTAssertGreaterThan(update(fontSize: 34.0, adaptive: true).height, 52.0)
        XCTAssertEqual(update(fontSize: 34.0, adaptive: false).height, 52.0)
        XCTAssertEqual(update(fontSize: 17.0, adaptive: true).height, 52.0)
    }

    func testLabelsAndDisabledActionsFollowTheCurrentState() throws {
        let host = ComponentView<Empty>()
        var activations = 0
        func update(label: String, enabled: Bool, allowWhenDisabled: Bool = false, progress: Bool = false) throws -> UIButton {
            let _ = host.update(
                transition: .immediate,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(color: .blue, foreground: .white, pressedColor: .blue),
                    content: AnyComponentWithIdentity(id: 0, component: AnyComponent(Text(text: label, font: Font.semibold(17.0), color: .white))),
                    accessibilityLabel: label,
                    isEnabled: enabled,
                    allowActionWhenDisabled: allowWhenDisabled,
                    displaysProgress: progress,
                    action: { activations += 1 }
                )),
                environment: {},
                containerSize: CGSize(width: 260.0, height: 52.0)
            )
            func findButton(_ view: UIView) -> UIButton? {
                if let button = view as? UIButton, button.accessibilityLabel == label {
                    return button
                }
                for child in view.subviews {
                    if let result = findButton(child) {
                        return result
                    }
                }
                return nil
            }
            return try XCTUnwrap(findButton(try XCTUnwrap(host.view)))
        }

        let enabled = try update(label: "Continue", enabled: true)
        XCTAssertTrue(enabled.isEnabled)
        enabled.sendActions(for: .touchUpInside)
        XCTAssertEqual(activations, 1)

        let disabled = try update(label: "Unavailable", enabled: false)
        XCTAssertFalse(disabled.isEnabled)
        disabled.sendActions(for: .touchUpInside)
        XCTAssertEqual(activations, 1)

        let explanation = try update(label: "Why unavailable?", enabled: false, allowWhenDisabled: true)
        XCTAssertTrue(explanation.isEnabled)
        explanation.sendActions(for: .touchUpInside)
        XCTAssertEqual(activations, 2)

        let loading = try update(label: "Loading", enabled: true, allowWhenDisabled: true, progress: true)
        XCTAssertFalse(loading.isEnabled)
        loading.sendActions(for: .touchUpInside)
        XCTAssertEqual(activations, 2)
    }
}
