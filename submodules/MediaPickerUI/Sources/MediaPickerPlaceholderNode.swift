import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import ComponentFlow
import ComponentDisplayAdapters
import EmptyStateIndicatorComponent
import TelegramPresentationData

final class MediaPickerPlaceholderNode: ASDisplayNode {
    enum Content {
        case intro(story: Bool)
        case bannedSendMedia(text: String, canBoost: Bool)
    }

    private let context: AccountContext
    private let indicator = ComponentView<Empty>()

    var boostPressed: () -> Void = {}
    var settingsPressed: () -> Void = {}
    var cameraPressed: () -> Void = {}

    init(context: AccountContext) {
        self.context = context
        super.init()
    }

    private func activatePrimaryAction(content: Content) {
        switch content {
        case .intro:
            self.settingsPressed()
        case .bannedSendMedia(_, true):
            self.boostPressed()
        case .bannedSendMedia(_, false):
            break
        }
    }

    private func activateCamera(content: Content, hasCamera: Bool) {
        if case .intro = content, hasCamera {
            self.cameraPressed()
        }
    }

    func update(content: Content, layout: ContainerViewLayout, navigationBarHeight: CGFloat, presentationData: PresentationData, hasCamera: Bool, transition: ContainedViewLayoutTransition) {
        let strings = presentationData.strings
        let title: String?
        let text: String
        let actionTitle: String?
        let cameraTitle: String?
        let animationName: String
        let animationIsLooping: Bool
        switch content {
        case let .intro(story):
            title = strings.Attachment_MediaAccessTitle
            text = story ? strings.Attachment_MediaAccessStoryText : strings.Attachment_MediaAccessText
            actionTitle = strings.Attachment_OpenSettings
            cameraTitle = hasCamera ? strings.Attachment_OpenCamera : nil
            animationName = "Photos"
            animationIsLooping = true
        case let .bannedSendMedia(description, canBoost):
            title = nil
            text = description
            actionTitle = canBoost ? strings.Attachment_BoostToUnlock : nil
            cameraTitle = nil
            animationName = "Banned"
            animationIsLooping = false
        }
        let insets = layout.insets(options: [])
        let topInset = max(insets.top, navigationBarHeight)
        let bottomInset = max(insets.bottom, layout.safeInsets.bottom)
        let availableSize = CGSize(width: max(1.0, layout.size.width - layout.safeInsets.left - layout.safeInsets.right), height: max(1.0, layout.size.height - topInset - bottomInset))
        let indicatorSize = self.indicator.update(
            transition: ComponentTransition(presentationData.reduceMotion ? .immediate : transition),
            component: AnyComponent(EmptyStateIndicatorComponent(
                context: self.context,
                theme: presentationData.theme,
                fitToHeight: false,
                animationName: animationName,
                title: title,
                text: text,
                actionTitle: actionTitle,
                action: { [weak self] in
                    self?.activatePrimaryAction(content: content)
                },
                additionalActionTitle: cameraTitle,
                additionalAction: { [weak self] in
                    self?.activateCamera(content: content, hasCamera: hasCamera)
                },
                fontSize: presentationData.listsFontSize.baseDisplaySize,
                reduceMotion: presentationData.reduceMotion,
                animationIsLooping: animationIsLooping
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
