import Foundation
import UIKit
import ObjectiveC
import Display
import LegacyComponents
import SSignalKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

enum SecureIdAttachmentIntent {
    case `default`
    case identityCard
    case multiple
    case selfie
}

func secureIdRecognizedDocumentData(from value: SecureIdMRZ) -> SecureIdRecognizedDocumentData {
    var issuingCountry: String?
    if let issuingCountryValue = value.issuingCountry {
        issuingCountry = countryCodeAlpha3ToAlpha2(issuingCountryValue)
    }
    var nationality: String?
    if let nationalityValue = value.nationality {
        nationality = countryCodeAlpha3ToAlpha2(nationalityValue)
    }
    return SecureIdRecognizedDocumentData(documentType: value.documentType, documentSubtype: value.documentSubtype, issuingCountry: issuingCountry, nationality: nationality, lastName: value.lastName.capitalized, firstName: value.firstName.capitalized, documentNumber: value.documentNumber, birthDate: value.birthDate, gender: value.gender, expiryDate: value.expiryDate)
}

func presentSecureIdAttachmentMenuImpl(presentationData: PresentationData, context: LegacyComponentsContext, parentController: TGViewController, intent: SecureIdAttachmentIntent, uploadAction: @escaping (SSignal?, (() -> Void)?) -> Void) -> TGMenuSheetController? {
    guard let controller = TGMenuSheetController(context: context, dark: false) else {
        return nil
    }
    controller.dismissesByOutsideTap = true
    controller.hasSwipeGesture = true
    
    var itemViews: [UIView] = []
    var underlyingViews: [UIView] = []
    
    let carouselItem = TGAttachmentCarouselItemView(context: context, camera: true, selfPortrait: intent == .selfie, forProfilePhoto: false, assetType: TGMediaAssetPhotoType, saveEditedPhotos: false, allowGrouping: false, allowSelection: intent == .multiple, allowEditing: true, document: true, selectionLimit: 10)!
    carouselItem.onlyCrop = true
    carouselItem.parentController = parentController
    carouselItem.cameraPressed = { [weak controller, weak parentController] cameraView in
        guard let controller, let parentController else {
            return
        }
        displaySecureIdAttachmentCamera(cameraView: cameraView, menuController: controller, parentController: parentController, context: context, intent: intent, uploadAction: uploadAction)
    }
    carouselItem.sendPressed = { [weak controller, weak carouselItem] currentItem, _, _, _, _ in
        guard let carouselItem else {
            return
        }
        uploadAction(secureIdAttachmentResultSignal(editingContext: carouselItem.editingContext, selectionContext: carouselItem.selectionContext, currentItem: currentItem as? TGMediaEditableItem), {
            controller?.dismiss(animated: true)
        })
    }
    itemViews.append(carouselItem)
    
    let galleryItem = TGMenuSheetButtonItemView(title: presentationData.strings.Common_ChoosePhoto, type: TGMenuSheetButtonTypeDefault, fontSize: 20.0, action: { [weak controller, weak parentController] in
        guard let parentController else {
            return
        }
        controller?.dismiss(animated: true)
        displaySecureIdAttachmentMediaPicker(parentController: parentController, context: context, intent: intent, uploadAction: uploadAction)
    })!
    itemViews.append(galleryItem)
    underlyingViews.append(galleryItem)
    
    if intent != .selfie {
        let iCloudItem = TGMenuSheetButtonItemView(title: presentationData.strings.Conversation_FileICloudDrive, type: TGMenuSheetButtonTypeDefault, fontSize: 20.0, action: { [weak controller, weak parentController] in
            guard let parentController else {
                return
            }
            controller?.dismiss(animated: true)
            presentSecureIdICloudPicker(parentController: parentController, uploadAction: uploadAction)
        })!
        itemViews.append(iCloudItem)
        underlyingViews.append(iCloudItem)
    }
    
    carouselItem.underlyingViews = underlyingViews
    carouselItem.remainingHeight = TGMenuSheetButtonItemViewHeight * CGFloat(itemViews.count - 1)
    
    let cancelItem = TGMenuSheetButtonItemView(title: presentationData.strings.Common_Cancel, type: TGMenuSheetButtonTypeCancel, fontSize: 20.0, action: { [weak controller] in
        controller?.dismiss(animated: true)
    })!
    itemViews.append(cancelItem)
    
    controller.permittedArrowDirections = [.up, .down]
    controller.forceFullScreen = true
    controller.setItemViews(itemViews)
    controller.present(in: parentController, sourceView: nil, animated: true)
    
    return controller
}

private func displaySecureIdAttachmentMediaPicker(parentController: TGViewController, context: LegacyComponentsContext, intent: SecureIdAttachmentIntent, uploadAction: @escaping (SSignal?, (() -> Void)?) -> Void) {
    if !LegacyComponentsGlobals.provider().accessChecker().checkPhotoAuthorizationStatus(for: TGPhotoAccessIntentRead, alertDismissCompletion: nil) {
        return
    }
    
    let showMediaPicker: (TGMediaAssetGroup?) -> Void = { [weak parentController] group in
        guard let parentController else {
            return
        }
        let assetsIntent: TGMediaAssetsControllerIntent = intent == .multiple ? TGMediaAssetsControllerPassportMultipleIntent : TGMediaAssetsControllerPassportIntent
        guard let controller = TGMediaAssetsController(context: context, assetGroup: group, intent: assetsIntent, recipientName: nil, saveEditedPhotos: false, allowGrouping: false, inhibitSelection: false, selectionLimit: 10) else {
            return
        }
        controller.onlyCrop = true
        controller.singleCompletionBlock = { [weak controller] currentItem, editingContext in
            guard let controller else {
                return
            }
            uploadAction(secureIdAttachmentResultSignal(editingContext: editingContext, selectionContext: controller.selectionContext, currentItem: currentItem as? TGMediaEditableItem), {
                controller.dismissalBlock?()
            })
        }
        controller.dismissalBlock = { [weak controller] in
            guard let controller else {
                return
            }
            if let customDismissSelf = controller.customDismissSelf {
                customDismissSelf()
            } else {
                controller.presentingViewController?.dismiss(animated: true)
            }
        }
        parentController.present(controller, animated: true)
    }
    
    if TGMediaAssetsLibrary.authorizationStatus() == TGMediaLibraryAuthorizationStatusNotDetermined {
        TGMediaAssetsLibrary.requestAuthorization(for: TGMediaAssetAnyType, completion: { _, group in
            if !LegacyComponentsGlobals.provider().accessChecker().checkPhotoAuthorizationStatus(for: TGPhotoAccessIntentRead, alertDismissCompletion: nil) {
                return
            }
            Queue.mainQueue().async {
                showMediaPicker(group)
            }
        })
    } else {
        showMediaPicker(nil)
    }
}

private func displaySecureIdAttachmentCamera(cameraView: TGAttachmentCameraView?, menuController: TGMenuSheetController, parentController: TGViewController, context: LegacyComponentsContext, intent: SecureIdAttachmentIntent, uploadAction: @escaping (SSignal?, (() -> Void)?) -> Void) {
    if !LegacyComponentsGlobals.provider().accessChecker().checkCameraAuthorizationStatus(for: TGCameraAccessIntentDefault, completion: { _ in }, alertDismissCompletion: nil) {
        return
    }
    if context.currentlyInSplitView() {
        return
    }
    
    let windowManager = context.makeOverlayWindowManager()
    let cameraIntent: TGCameraControllerIntent
    switch intent {
    case .identityCard:
        cameraIntent = TGCameraControllerPassportIdIntent
    case .multiple:
        cameraIntent = TGCameraControllerPassportMultipleIntent
    default:
        cameraIntent = TGCameraControllerPassportIntent
    }
    
    let controller: TGCameraController
    if let cameraView, let previewView = cameraView.previewView() {
        if intent == .selfie {
            previewView.camera.disableResultMirroring = true
        }
        controller = TGCameraController(context: windowManager?.context(), saveEditedPhotos: false, saveCapturedMedia: false, camera: previewView.camera, previewView: previewView, intent: cameraIntent)
    } else {
        controller = TGCameraController(context: windowManager?.context(), saveEditedPhotos: false, saveCapturedMedia: false, intent: cameraIntent)
    }
    controller.shouldStoreCapturedAssets = false
    
    guard let controllerWindow = TGCameraControllerWindow(manager: windowManager, parentController: parentController, contentController: controller) else {
        return
    }
    controllerWindow.isHidden = false
    controllerWindow.clipsToBounds = true
    
    let screenSize = parentController.view.bounds.size
    controllerWindow.frame = UIDevice.current.userInterfaceIdiom == .phone ? CGRect(origin: .zero, size: screenSize) : context.fullscreenBounds()
    
    var startFrame = CGRect(x: 0.0, y: screenSize.height, width: screenSize.width, height: screenSize.height)
    if let cameraView, let previewView = cameraView.previewView() {
        startFrame = UIDevice.current.userInterfaceIdiom == .pad ? .zero : controller.view.convert(previewView.frame, from: cameraView)
    }
    
    cameraView?.detachPreviewView()
    controller.beginTransitionIn(from: startFrame)
    controller.beginTransitionOut = { [weak controller, weak cameraView] in
        guard let controller, let cameraView else {
            return CGRect.zero
        }
        cameraView.willAttachPreviewView()
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .zero
        }
        return controller.view.convert(cameraView.frame, from: cameraView.superview)
    }
    controller.finishedTransitionOut = { [weak cameraView] in
        cameraView?.attachPreviewView(animated: true)
    }
    controller.finishedWithResults = { [weak menuController] _, selectionContext, editingContext, currentItem, _, _ in
        menuController?.dismiss(animated: false)
        uploadAction(secureIdAttachmentResultSignal(editingContext: editingContext, selectionContext: selectionContext, currentItem: currentItem as? TGMediaEditableItem), {})
    }
}

private func presentSecureIdICloudPicker(parentController: TGViewController, uploadAction: @escaping (SSignal?, (() -> Void)?) -> Void) {
    let delegate = SecureIdDocumentPickerDelegate { urls in
        if let url = urls.first {
            uploadAction(SSignal.single(url), {})
        }
    }
    let controller = UIDocumentPickerViewController(documentTypes: ["public.image"], in: .open)
    controller.view.backgroundColor = .white
    controller.delegate = delegate
    controller.secureIdDelegate = delegate
    if UIDevice.current.userInterfaceIdiom == .pad {
        controller.modalPresentationStyle = .formSheet
    }
    parentController.present(controller, animated: true)
}

private final class SecureIdDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: ([URL]) -> Void
    
    init(completion: @escaping ([URL]) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls)
        controller.secureIdDelegate = nil
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        self.completion([url])
        controller.secureIdDelegate = nil
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion([])
        controller.secureIdDelegate = nil
    }
}

private var secureIdDocumentPickerDelegateKey: UInt8 = 0

private extension UIDocumentPickerViewController {
    var secureIdDelegate: SecureIdDocumentPickerDelegate? {
        get {
            return objc_getAssociatedObject(self, &secureIdDocumentPickerDelegateKey) as? SecureIdDocumentPickerDelegate
        }
        set {
            objc_setAssociatedObject(self, &secureIdDocumentPickerDelegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private struct SecureIdICloudFileDescription {
    let urlData: String
    
    init?(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        guard let bookmarkData = try? url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) != nil else {
            return nil
        }
        guard url.lastPathComponent.removingPercentEncoding != nil else {
            return nil
        }
        self.urlData = bookmarkData.base64EncodedString()
    }
}

private func secureIdICloudFileDescription(for url: URL) -> Signal<SecureIdICloudFileDescription?, NoError> {
    return Signal { subscriber in
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        let isRemote = values?.ubiquitousItemDownloadingStatus != nil
        let isCurrent = values?.ubiquitousItemDownloadingStatus == .current
        if !isRemote || isCurrent {
            subscriber.putNext(SecureIdICloudFileDescription(url: url))
            subscriber.putCompletion()
        } else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
        }
        return EmptyDisposable
    }
}

func fetchSecureIdICloudFile(with url: URL) -> Signal<URL?, NoError> {
    return secureIdICloudFileDescription(for: url)
    |> mapToSignal { description -> Signal<URL?, NoError> in
        guard let description, let urlData = Data(base64Encoded: description.urlData) else {
            return .complete()
        }
        return Signal { subscriber in
            var bookmarkIsStale = false
            guard let resolvedURL = try? URL(resolvingBookmarkData: urlData, options: [], relativeTo: nil, bookmarkDataIsStale: &bookmarkIsStale), resolvedURL.startAccessingSecurityScopedResource() else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let targetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("icloud_doc\(Int.random(in: 0 ... Int.max))")
            let _ = try? FileManager.default.copyItem(at: resolvedURL, to: targetURL)
            resolvedURL.stopAccessingSecurityScopedResource()
            subscriber.putNext(targetURL)
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}

private func secureIdAttachmentResultSignal(editingContext: TGMediaEditingContext?, selectionContext: TGMediaSelectionContext?, currentItem: TGMediaEditableItem?) -> SSignal {
    var signal = SSignal.complete()
    var selectedItems = selectionContext?.selectedItems() as? [TGMediaEditableItem] ?? []
    if selectedItems.isEmpty, let currentItem {
        selectedItems.append(currentItem)
    }
    
    for item in selectedItems {
        var inlineSignal: SSignal?
        if let asset = item as? TGMediaAsset {
            inlineSignal = TGMediaAssetImageSignals.image(for: asset, imageType: TGMediaAssetImageTypeScreen, size: CGSize(width: 2048.0, height: 2048.0), allowNetworkAccess: false)
        } else if let photo = item as? TGCameraCapturedPhoto {
            inlineSignal = photo.originalImageSignal(0.0)
        }
        guard let inlineSignal else {
            continue
        }
        
        let imageSignal: SSignal
        if let editingContext {
            imageSignal = editingContext.imageSignal(for: item, withUpdates: true)
                .filter { result in
                    guard let result else {
                        return true
                    }
                    guard let image = result as? UIImage else {
                        return false
                    }
                    return !image.degraded()
                }
                .take(1)
                .map(toSignal: { result -> SSignal in
                    guard let result else {
                        return SSignal.fail(nil)
                    }
                    if let image = result as? UIImage {
                        image.edited = true
                        return SSignal.single(image)
                    }
                    return SSignal.complete()
                })
                .onCompletion {
                    _ = editingContext.description
                }
        } else {
            imageSignal = inlineSignal
        }
        
        signal = signal.then(imageSignal.catch { _ in
            return inlineSignal
        }.map { value in
            guard let image = value as? UIImage else {
                return [:]
            }
            let maxSide: CGFloat = 2048.0
            let imageSize = image.size.aspectFitted(CGSize(width: maxSide, height: maxSide))
            let scaledImage = max(image.size.width, image.size.height) > maxSide ? TGScaleImageToPixelSize(image, imageSize) : image
            let thumbnailSide = 60.0 * UIScreenScale
            let thumbnailSize = scaledImage?.size.aspectFitted(CGSize(width: thumbnailSide, height: thumbnailSide)) ?? .zero
            let thumbnailImage = scaledImage.flatMap { TGScaleImageToPixelSize($0, thumbnailSize) }
            
            var result: [String: Any] = [:]
            if let scaledImage {
                result["image"] = scaledImage
            }
            if let thumbnailImage {
                result["thumbnail"] = thumbnailImage
            }
            return result
        })
    }
    return signal
}
