import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import AccountContext
import SwiftUI
import TelegramUIPreferences

public func presentTranslateScreen(
    context: AccountContext,
    text: String,
    entities: [MessageTextEntity] = [],
    canCopy: Bool,
    fromLanguage: String?,
    toLanguage: String? = nil,
    isExpanded: Bool = false,
    ignoredLanguages: [String]? = nil,
    replaceText: ((String, [MessageTextEntity]) -> Void)? = nil,
    translateChat: ((String, String) -> Void)? = nil,
    pushController: @escaping (ViewController) -> Void = { _ in },
    presentController: @escaping (ViewController) -> Void = { _ in },
    wasDismissed: (() -> Void)? = nil,
    display: (ViewController) -> Void
) {
    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var useSystemTranslation = false
    switch translationConfiguration.manual {
    case .system:
        if #available(iOS 18.0, *) {
            useSystemTranslation = true
        }
    default:
        break
    }
    // Let the user force Apple's on-device system translation regardless of what the server's
    // translation config says — a free alternative independent of Telegram's own backend.
    if !useSystemTranslation, context.sharedContext.immediateForkExtrasSettings.translationBackend == .system, #available(iOS 18.0, *) {
        useSystemTranslation = true
    }

    if useSystemTranslation {
        presentSystemTranslateScreen(context: context, text: text, replaceText: replaceText)
    } else {
    }
}

private func presentSystemTranslateScreen(context: AccountContext, text: String, replaceText: ((String, [MessageTextEntity]) -> Void)?) {
    if #available(iOS 18.0, *), let rootViewController = context.sharedContext.mainWindow?.viewController?.view.window?.rootViewController {
        var dismissImpl: (() -> Void)?
        // The composer's Translate passes `replaceText`: the system sheet then shows Replace with Translation, which
        // puts the translation into the input field. Without it the sheet could only show and copy the result.
        let replacement: ((String) -> Void)? = replaceText.flatMap { replaceText in
            return { translated in
                DispatchQueue.main.async {
                    replaceText(translated, [])
                }
            }
        }
        let pickerView = TranslateScreenHostingView(text: text, replacementAction: replacement, completionHandler: { [weak rootViewController] in
            DispatchQueue.main.async(execute: {
                guard let presentedController = rootViewController?.presentedViewController, presentedController.isBeingDismissed == false else { return }
                dismissImpl?()
            })
        })
        let hostingController = UIHostingController(rootView: pickerView)
        hostingController.view.isHidden = true
        hostingController.modalPresentationStyle = .overCurrentContext
        rootViewController.present(hostingController, animated: true)
        dismissImpl = { [weak hostingController] in
            Queue.mainQueue().after(0.4, {
                hostingController?.dismiss(animated: false)
            })
        }
    }
}

@available(iOS 18.0, *)
struct TranslateScreenHostingView: View {
    @State var presented = true
    var text: String
    var replacementAction: ((String) -> Void)?
    var handler: () -> Void

    init(text: String, replacementAction: ((String) -> Void)?, completionHandler: @escaping () -> Void) {
        self.text = text
        self.replacementAction = replacementAction
        self.handler = completionHandler
    }
    
    var body: some View {
        Spacer()
            .translationPresentation(
                isPresented: $presented,
                text: text,
                replacementAction: replacementAction
            )
            .onChange(of: presented) { newValue in
                if newValue == false {
                    handler()
                }
            }
    }
}
