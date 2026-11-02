import Foundation
import UIKit
import XCTest
import ButtonComponent
import ComponentFlow
import Display

final class ButtonAccessibilityTests: XCTestCase {
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
