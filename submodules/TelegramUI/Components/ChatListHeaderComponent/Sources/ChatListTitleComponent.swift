import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import TelegramPresentationData
import AccountContext
import ChatListTitleView
import NavigationBarComponent

/// The chat list's title (`ChatListTitleView`: network status, lock, emoji status) as a row-filling
/// `NavigationBarComponent` title. While the stories are collapsed into the title (`sideContentFraction` 1), it
/// slides left to keep clear of the right buttons.
final class ChatListTitleComponent: Component {
    typealias EnvironmentType = NavigationBarTitleEnvironment

    let context: AccountContext
    let theme: PresentationTheme
    let strings: PresentationStrings
    let title: NetworkStatusTitle
    let sideContentFraction: CGFloat
    /// The fork's "centered title" option: the title takes the free space between the buttons and sits at the
    /// bar's center as far as that space allows.
    let centered: Bool
    let openStatusSetup: (UIView) -> Void
    let toggleIsLocked: () -> Void

    init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings, title: NetworkStatusTitle, sideContentFraction: CGFloat, centered: Bool = false, openStatusSetup: @escaping (UIView) -> Void, toggleIsLocked: @escaping () -> Void) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.title = title
        self.sideContentFraction = sideContentFraction
        self.centered = centered
        self.openStatusSetup = openStatusSetup
        self.toggleIsLocked = toggleIsLocked
    }

    static func ==(lhs: ChatListTitleComponent, rhs: ChatListTitleComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.title != rhs.title {
            return false
        }
        if lhs.sideContentFraction != rhs.sideContentFraction {
            return false
        }
        if lhs.centered != rhs.centered {
            return false
        }
        return true
    }

    final class View: UIView {
        private(set) var titleView: ChatListTitleView?
        private var component: ChatListTitleComponent?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let titleView = self.titleView else {
                return nil
            }
            return titleView.hitTest(self.convert(point, to: titleView), with: event)
        }

        func update(component: ChatListTitleComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<NavigationBarTitleEnvironment>, transition: ComponentTransition) -> CGSize {
            self.component = component
            let titleEnvironment = environment[NavigationBarTitleEnvironment.self].value
            let leftButtonsExtent = titleEnvironment.leftButtonsExtent
            let rightButtonsExtent = titleEnvironment.rightButtonsExtent

            var titleTransition = transition
            let titleView: ChatListTitleView
            if let current = self.titleView {
                titleView = current
            } else {
                titleTransition = .immediate
                titleView = ChatListTitleView(context: component.context, theme: component.theme, strings: component.strings, animationCache: component.context.animationCache, animationRenderer: component.context.animationRenderer)
                titleView.manualLayout = true
                self.titleView = titleView
                self.addSubview(titleView)
            }

            titleView.theme = component.theme
            titleView.strings = component.strings
            titleView.setTitle(component.title, animated: false)
            // Centered: the title gets the free space between the buttons rather than a box mirrored from the wider side.
            let titleAreaMinX = leftButtonsExtent + 8.0
            let titleContentSize = component.centered ? CGSize(width: max(1.0, availableSize.width - rightButtonsExtent - 8.0 - titleAreaMinX), height: availableSize.height) : availableSize
            let titleContentRect = titleView.updateLayoutInternal(size: titleContentSize, transition: transition.containedViewLayoutTransition, centerTitle: component.centered)
            let centerContentOffsetX = -max(0.0, titleContentRect.maxX - 2.0 - (availableSize.width - rightButtonsExtent))

            titleView.openStatusSetup = { [weak self] sourceView in
                guard let self else {
                    return
                }
                self.component?.openStatusSetup(sourceView)
            }
            titleView.toggleIsLocked = { [weak self] in
                guard let self else {
                    return
                }
                self.component?.toggleIsLocked()
            }

            let titleOffset: CGFloat
            if component.centered {
                // 0 puts the title at the bar's center; keep the offset where the title stays inside the free space. The activity
                // indicator is outside the rect but centered with the title, so the room on its left is at most the room on its right.
                let titleRightSpace = max(0.0, titleContentSize.width - titleContentRect.maxX)
                let titleLeftSpace = max(0.0, min(titleContentRect.minX, titleRightSpace))
                let titleAreaOffset = titleAreaMinX - floor((availableSize.width - titleContentSize.width) / 2.0)
                titleOffset = max(titleAreaOffset - titleLeftSpace, min(titleAreaOffset + titleRightSpace, 0.0))
            } else if component.title.activity {
                titleOffset = 0.0
            } else {
                titleOffset = centerContentOffsetX * component.sideContentFraction
            }
            titleTransition.setFrame(view: titleView, frame: CGRect(origin: CGPoint(x: titleOffset + floor((availableSize.width - titleContentSize.width) / 2.0), y: floor((availableSize.height - titleContentSize.height) / 2.0)), size: titleContentSize))

            return availableSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<NavigationBarTitleEnvironment>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
