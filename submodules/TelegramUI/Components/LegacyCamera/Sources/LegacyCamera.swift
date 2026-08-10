import Foundation
import UIKit
import LegacyComponents
import Display
import TelegramCore
import SwiftSignalKit
import AccountContext
import ShareController
import LegacyUI
import LegacyMediaPickerUI

public func presentedLegacyShortcutCamera(context: AccountContext, saveCapturedMedia: Bool, saveEditedPhotos: Bool, mediaGrouping: Bool, parentController: ViewController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let legacyController = LegacyController(presentation: .custom, theme: presentationData.theme)
    legacyController.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .portrait, compactSize: .portrait)
    legacyController.statusBar.statusBarStyle = .Hide
    
    legacyController.deferScreenEdgeGestures = [.top]
    
    let controller = TGCameraController(context: legacyController.context, saveEditedPhotos: saveEditedPhotos, saveCapturedMedia: saveCapturedMedia)!
    controller.shortcut = false
    controller.isImportant = true
    controller.shouldStoreCapturedAssets = saveCapturedMedia
    controller.allowCaptions = true
    controller.allowCaptionEntities = true
    controller.allowGrouping = mediaGrouping
    
    let screenSize = parentController.view.bounds.size
    let startFrame = CGRect(x: 0, y: screenSize.height, width: screenSize.width, height: screenSize.height)
    
    legacyController.bind(controller: controller)
    legacyController.controllerLoaded = { [weak controller] in
        if let controller = controller {
            controller.beginTransitionIn(from: startFrame)
        }
    }
    
    controller.finishedTransitionOut = { [weak legacyController] in
        legacyController?.dismiss()
    }
    
    controller.customDismissBlock = { [weak legacyController] in
        legacyController?.dismiss()
    }
    
    controller.finishedWithResults = { [weak parentController] overlayController, selectionContext, editingContext, currentItem, _, _ in
        if let selectionContext = selectionContext, let editingContext = editingContext {
            let nativeGenerator = legacyAssetPickerItemGenerator()
            let signals = TGCameraController.resultSignals(for: selectionContext, editingContext: editingContext, currentItem: currentItem, storeAssets: saveCapturedMedia, saveEditedPhotos: saveEditedPhotos, descriptionGenerator: { _1, _2, _3 in
                nativeGenerator(_1, _2, _3, nil)
            })
            if let parentController = parentController {
                parentController.present(context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .fromExternal(1, { peerIds, _, _, text, account, silently in
                    guard let account = account as? ShareControllerAppAccountContext else {
                        return .single(.done)
                    }
                    return legacyAssetPickerEnqueueMessages(context: context, account: account.context.account, signals: signals!)
                    |> `catch` { _ -> Signal<[LegacyAssetPickerEnqueueMessage], ShareControllerError> in
                        return .single([])
                    }
                    |> mapToSignal { messages -> Signal<ShareControllerExternalStatus, ShareControllerError> in
                        let resultSignals = peerIds.map({ peerId in
                            return enqueueMessages(account: account.context.account, peerId: peerId, messages: messages.map { $0.message })
                            |> castError(ShareControllerError.self)
                            |> mapToSignal { _ -> Signal<ShareControllerExternalStatus, ShareControllerError> in
                                return .complete()
                            }
                        })
                        return combineLatest(resultSignals)
                        |> mapToSignal { _ -> Signal<ShareControllerExternalStatus, ShareControllerError> in
                            return .complete()
                        }
                        |> then(.single(ShareControllerExternalStatus.done))
                    }
                }), showInChat: nil, externalShare: false)), in: .window(.root))
            }
        }
    }
    
    parentController.present(legacyController, in: .window(.root))
}
