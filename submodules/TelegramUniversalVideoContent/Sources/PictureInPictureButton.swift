import Foundation
import UIKit

/// Round blurred control used by the picture-in-picture overlay.
///
/// Migrated from `TGEmbedPIPButton` in LegacyComponents. It qualified as the first Objective-C
/// class to move because it is a graph singleton — it imports nothing from LegacyComponents, and
/// this file is its only consumer — so the Swift version needs no new Bazel target and no
/// Objective-C anywhere has to import a generated Swift header.
final class PictureInPictureButton: UIButton {
    static let size = CGSize(width: 42.0, height: 42.0)

    private let backView: UIVisualEffectView
    private let highlightView: UIView
    private let iconView: UIImageView

    /// Highlight changes animate only when they come from touch tracking. A programmatic change
    /// snaps, matching the original.
    private var animateHighlight = false

    override init(frame: CGRect) {
        self.backView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        self.highlightView = UIView()
        self.iconView = UIImageView()

        super.init(frame: frame)

        self.clipsToBounds = true
        self.isExclusiveTouch = true

        self.backView.frame = self.bounds
        self.backView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.backView.isUserInteractionEnabled = false
        self.addSubview(self.backView)

        self.highlightView.frame = self.bounds
        self.highlightView.alpha = 0.0
        self.highlightView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.highlightView.backgroundColor = .white
        self.highlightView.isUserInteractionEnabled = false
        self.addSubview(self.highlightView)

        self.iconView.frame = self.bounds
        self.iconView.contentMode = .center
        self.addSubview(self.iconView)

        // The original only rounded the corners from its setFrame: override, which UIView does not
        // necessarily route through during init. Setting it here too means the button is never
        // drawn square on its first frame.
        self.updateCornerRadius()
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    override var frame: CGRect {
        didSet {
            self.updateCornerRadius()
        }
    }

    private func updateCornerRadius() {
        self.layer.cornerRadius = self.frame.size.width / 2.0
    }

    func setIconImage(_ iconImage: UIImage?) {
        self.iconView.image = iconImage
    }

    override var isHighlighted: Bool {
        didSet {
            let apply: () -> Void = { [weak self] in
                self?.highlightView.alpha = self?.isHighlighted == true ? 1.0 : 0.0
            }
            if self.animateHighlight {
                UIView.animate(withDuration: 0.2, animations: apply)
            } else {
                apply()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.animateHighlight = true
        super.touchesMoved(touches, with: event)
        self.animateHighlight = false
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.animateHighlight = true
        super.touchesEnded(touches, with: event)
        self.animateHighlight = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.animateHighlight = true
        super.touchesCancelled(touches, with: event)
        self.animateHighlight = false
    }
}
