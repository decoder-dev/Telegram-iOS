import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import ComponentFlow
import ComponentDisplayAdapters
import EmptyStateIndicatorComponent
import TelegramPresentationData

final class LocationPlaceholderNode: ASDisplayNode {
    private let context: AccountContext
    private let indicator = ComponentView<Empty>()

    var settingsPressed: () -> Void = {}

    init(context: AccountContext) {
        self.context = context
        super.init()
    }

    func update(layout: ContainerViewLayout, navigationHeight: CGFloat, presentationData: PresentationData, transition: ContainedViewLayoutTransition) {
        let insets = layout.insets(options: [])
        let topInset = max(insets.top, navigationHeight)
        let bottomInset = max(insets.bottom, layout.safeInsets.bottom)
        let availableSize = CGSize(width: max(1.0, layout.size.width - layout.safeInsets.left - layout.safeInsets.right), height: max(1.0, layout.size.height - topInset - bottomInset))
        let indicatorSize = self.indicator.update(
            transition: ComponentTransition(presentationData.reduceMotion ? .immediate : transition),
            component: AnyComponent(EmptyStateIndicatorComponent(
                context: self.context,
                theme: presentationData.theme,
                fitToHeight: false,
                animationName: "Location",
                title: presentationData.strings.Attachment_LocationAccessTitle,
                text: presentationData.strings.Attachment_LocationAccessText,
                actionTitle: presentationData.strings.Attachment_OpenSettings,
                action: { [weak self] in
                    self?.settingsPressed()
                },
                additionalActionTitle: nil,
                additionalAction: {},
                fontSize: presentationData.listsFontSize.baseDisplaySize,
                reduceMotion: presentationData.reduceMotion
            )),
            environment: {},
            containerSize: availableSize
        )
        if let view = self.indicator.view {
            if view.superview == nil {
                self.view.addSubview(view)
            }
            transition.updateFrame(view: view, frame: CGRect(origin: CGPoint(x: layout.safeInsets.left, y: topInset), size: indicatorSize))
        }
    }
}
