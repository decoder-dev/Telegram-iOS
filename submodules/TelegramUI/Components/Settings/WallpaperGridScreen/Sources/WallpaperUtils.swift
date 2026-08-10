import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import MediaResources
import LocalMediaResources
import TelegramUIPreferences
import AccountContext
import WallpaperGalleryScreen
import ImageBlur

private func wallpaperScreenSize() -> CGSize {
    let screen = UIScreen.main
    return screen.coordinateSpace.convert(screen.bounds, to: screen.fixedCoordinateSpace).size
}

/// Axis-aligned crop used by wallpaper apply paths (orientation `.up`, no paint /
/// rotation / mirror). Replaces `TGPhotoEditorCrop` so WallpaperGridScreen no
/// longer imports LegacyComponents for this one C helper.
private func cropWallpaperImage(_ image: UIImage, cropRect: CGRect, maxSize: CGSize) -> UIImage {
    let fittedImageSize = cropRect.size.fitted(maxSize)
    let outputSize = CGSize(width: floor(fittedImageSize.width), height: floor(fittedImageSize.height))
    guard outputSize.width > 0.0, outputSize.height > 0.0 else {
        return image
    }
    
    UIGraphicsBeginImageContextWithOptions(outputSize, true, 1.0)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else {
        return image
    }
    
    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(origin: .zero, size: outputSize))
    context.interpolationQuality = .high
    
    let scaleX = outputSize.width / max(cropRect.width, 1.0)
    let scaleY = outputSize.height / max(cropRect.height, 1.0)
    let drawRect = CGRect(
        x: -cropRect.origin.x * scaleX,
        y: -cropRect.origin.y * scaleY,
        width: image.size.width * scaleX,
        height: image.size.height * scaleY
    )
    image.draw(in: drawRect)
    return UIGraphicsGetImageFromCurrentImageContext() ?? image
}

private func defaultWallpaperCropRect(for image: UIImage) -> CGRect {
    let fittedSize = wallpaperScreenSize().fitted(image.size)
    return CGRect(
        x: (image.size.width - fittedSize.width) / 2.0,
        y: (image.size.height - fittedSize.height) / 2.0,
        width: fittedSize.width,
        height: fittedSize.height
    )
}

public func uploadCustomWallpaper(context: AccountContext, wallpaper: WallpaperGalleryEntry, mode: WallpaperPresentationOptions, editedImage: UIImage?, cropRect: CGRect?, brightness: CGFloat?, completion: @escaping () -> Void) {
    var imageSignal: Signal<UIImage, NoError>
    switch wallpaper {
        case let .wallpaper(wallpaper, _):
            switch wallpaper {
                case let .file(file):
                    if let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(file.file.resource.id)), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead) {
                        context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(file.file.resource.id), data: data)
                        let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(file.file.resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start()
                        let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(file.file.resource, representation: CachedBlurredWallpaperRepresentation(), complete: true, fetch: true).start()
                    }
                case let .image(representations, _):
                    for representation in representations {
                        let resource = representation.resource
                        if let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(resource.id)), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead) {
                            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
                            let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start()
                        }
                    }
                default:
                    break
            }
            imageSignal = .complete()
            completion()
        case let .asset(asset):
            imageSignal = fetchPhotoLibraryImage(localIdentifier: asset.localIdentifier, thumbnail: false)
            |> filter { value in
                return !(value?.1 ?? true)
            }
            |> mapToSignal { result -> Signal<UIImage, NoError> in
                if let result = result {
                    return .single(result.0)
                } else {
                    return .complete()
                }
            }
        case let .contextResult(result):
            var imageResource: TelegramMediaResource?
            switch result {
                case let .externalReference(externalReference):
                    if let content = externalReference.content {
                        imageResource = content.resource
                    }
                case let .internalReference(internalReference):
                    if let image = internalReference.image {
                        if let imageRepresentation = imageRepresentationLargerThan(image.representations, size: PixelDimensions(width: 1000, height: 800)) {
                            imageResource = imageRepresentation.resource
                        }
                    }
            }
            
            if let imageResource = imageResource {
                imageSignal = .single(context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(imageResource.id)))
                |> mapToSignal { path -> Signal<UIImage, NoError> in
                    if let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]), let image = UIImage(data: data) {
                        return .single(image)
                    } else {
                        return .complete()
                    }
                }
            } else {
                imageSignal = .complete()
            }
    }
    
    if let editedImage {
        imageSignal = .single(editedImage)
    }
    
    let _ = (imageSignal
    |> map { image -> UIImage in
        var croppedImage = UIImage()
        
        let finalCropRect = cropRect ?? defaultWallpaperCropRect(for: image)
        croppedImage = cropWallpaperImage(image, cropRect: finalCropRect, maxSize: CGSize(width: 1440.0, height: 2960.0))
        
        let thumbnailDimensions = finalCropRect.size.fitted(CGSize(width: 320.0, height: 320.0))
        let thumbnailImage = generateScaledImage(image: croppedImage, size: thumbnailDimensions, scale: 1.0)
        
        if let data = croppedImage.jpegData(compressionQuality: 0.8), let thumbnailImage = thumbnailImage, let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
            let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnailData, synchronous: true)
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnailData, synchronous: true)
            
            let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
            
            let autoNightModeTriggered = context.sharedContext.currentPresentationData.with {$0 }.autoNightModeTriggered
            let accountManager = context.sharedContext.accountManager
            let account = context.account
            let updateWallpaper: (TelegramWallpaper) -> Void = { wallpaper in
                var resource: TelegramMediaResource?
                if case let .image(representations, _) = wallpaper, let representation = largestImageRepresentation(representations) {
                    resource = representation.resource
                } else if case let .file(file) = wallpaper {
                    resource = file.file.resource
                }
                
                if let resource = resource {
                    let _ = accountManager.mediaBox.cachedResourceRepresentation(resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start(completed: {})
                    let _ = account.postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start(completed: {})
                }
                
                let _ = (updatePresentationThemeSettingsInteractively(accountManager: accountManager, { current in
                    var themeSpecificChatWallpapers = current.themeSpecificChatWallpapers
                    let themeReference: PresentationThemeReference
                    if autoNightModeTriggered {
                        themeReference = current.automaticThemeSwitchSetting.theme
                    } else {
                        themeReference = current.theme
                    }
                    let accentColor = current.themeSpecificAccentColors[themeReference.index]
                    if let accentColor = accentColor, accentColor.baseColor == .custom {
                        themeSpecificChatWallpapers[coloredThemeIndex(reference: themeReference, accentColor: accentColor)] = wallpaper
                    } else {
                        themeSpecificChatWallpapers[coloredThemeIndex(reference: themeReference, accentColor: accentColor)] = nil
                        themeSpecificChatWallpapers[themeReference.index] = wallpaper
                    }
                    return current.withUpdatedThemeSpecificChatWallpapers(themeSpecificChatWallpapers)
                })).start()
            }
            
            let apply: () -> Void = {
                let settings = WallpaperSettings(blur: mode.contains(.blur), motion: mode.contains(.motion), colors: [], intensity: nil)
                let wallpaper: TelegramWallpaper = .image([TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailDimensions), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false), TelegramMediaImageRepresentation(dimensions: PixelDimensions(croppedImage.size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)], settings)
                updateWallpaper(wallpaper)
                DispatchQueue.main.async {
                    completion()
                }
            }
            
            if mode.contains(.blur) {
                let representation = CachedBlurredWallpaperRepresentation()
                let _ = context.account.postbox.mediaBox.cachedResourceRepresentation(resource, representation: representation, complete: true, fetch: true).start()
                let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: representation, complete: true, fetch: true).start(completed: {
                    apply()
                })
            } else {
                apply()
            }
        }
        return croppedImage
    }).start()
}

public func getTemporaryCustomPeerWallpaper(context: AccountContext, wallpaper: WallpaperGalleryEntry, mode: WallpaperPresentationOptions, editedImage: UIImage?, cropRect: CGRect?, brightness: CGFloat?) -> Signal<TelegramWallpaper?, NoError> {
    var imageSignal: Signal<UIImage, NoError>
    switch wallpaper {
        case .wallpaper:
            fatalError()
        case let .asset(asset):
            imageSignal = fetchPhotoLibraryImage(localIdentifier: asset.localIdentifier, thumbnail: false)
            |> filter { value in
                return !(value?.1 ?? true)
            }
            |> mapToSignal { result -> Signal<UIImage, NoError> in
                if let result = result {
                    return .single(result.0)
                } else {
                    return .complete()
                }
            }
        case let .contextResult(result):
            var imageResource: TelegramMediaResource?
            switch result {
                case let .externalReference(externalReference):
                    if let content = externalReference.content {
                        imageResource = content.resource
                    }
                case let .internalReference(internalReference):
                    if let image = internalReference.image {
                        if let imageRepresentation = imageRepresentationLargerThan(image.representations, size: PixelDimensions(width: 1000, height: 800)) {
                            imageResource = imageRepresentation.resource
                        }
                    }
            }
            
            if let imageResource = imageResource {
                imageSignal = .single(context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(imageResource.id)))
                |> mapToSignal { path -> Signal<UIImage, NoError> in
                    if let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]), let image = UIImage(data: data) {
                        return .single(image)
                    } else {
                        return .complete()
                    }
                }
            } else {
                imageSignal = .complete()
            }
    }
    
    if let editedImage {
        imageSignal = .single(editedImage)
    }
    
    return imageSignal
    |> map { image -> TelegramWallpaper? in
        var croppedImage = UIImage()
        
        let finalCropRect = cropRect ?? defaultWallpaperCropRect(for: image)
        croppedImage = cropWallpaperImage(image, cropRect: finalCropRect, maxSize: CGSize(width: 1440.0, height: 2960.0))
                
        let thumbnailDimensions = finalCropRect.size.fitted(CGSize(width: 320.0, height: 320.0))
        let thumbnailImage = generateScaledImage(image: croppedImage, size: thumbnailDimensions, scale: 1.0)
        
        if let data = croppedImage.jpegData(compressionQuality: 0.8), let thumbnailImage = thumbnailImage, let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
            let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnailData, synchronous: true)
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnailData, synchronous: true)
            
            let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
            
            let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: CachedBlurredWallpaperRepresentation(), complete: true, fetch: true).start()
            
            var intensity: Int32?
            if let brightness {
                intensity = max(0, min(100, Int32(brightness * 100.0)))
            }
            
            let settings = WallpaperSettings(blur: mode.contains(.blur), motion: mode.contains(.motion), colors: [], intensity: intensity)
            let temporaryWallpaper: TelegramWallpaper = .image([TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailDimensions), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false), TelegramMediaImageRepresentation(dimensions: PixelDimensions(croppedImage.size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)], settings)
                
            return temporaryWallpaper
        }
        return nil
    }
}

public func uploadCustomPeerWallpaper(context: AccountContext, wallpaper: WallpaperGalleryEntry, mode: WallpaperPresentationOptions, editedImage: UIImage?, cropRect: CGRect?, brightness: CGFloat?, peerId: EnginePeer.Id, forBoth: Bool, completion: @escaping () -> Void) {
    var imageSignal: Signal<UIImage, NoError>
    switch wallpaper {
        case let .wallpaper(wallpaper, _):
            imageSignal = .complete()
            switch wallpaper {
                case let .file(file):
                    if let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(file.file.resource.id)), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead), let image = UIImage(data: data) {
                        context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(file.file.resource.id), data: data, synchronous: true)
                        let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(file.file.resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start()
                        let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(file.file.resource, representation: CachedBlurredWallpaperRepresentation(), complete: true, fetch: true).start()
                     
                        imageSignal = .single(image)
                    }
                case let .image(representations, _):
                    for representation in representations {
                        let resource = representation.resource
                        if let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(resource.id)), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead) {
                            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
                            let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: CachedScaledImageRepresentation(size: CGSize(width: 720.0, height: 720.0), mode: .aspectFit), complete: true, fetch: true).start()
                        }
                    }
                default:
                    break
            }
            completion()
        case let .asset(asset):
            imageSignal = fetchPhotoLibraryImage(localIdentifier: asset.localIdentifier, thumbnail: false)
            |> filter { value in
                return !(value?.1 ?? true)
            }
            |> mapToSignal { result -> Signal<UIImage, NoError> in
                if let result = result {
                    return .single(result.0)
                } else {
                    return .complete()
                }
            }
        case let .contextResult(result):
            var imageResource: TelegramMediaResource?
            switch result {
                case let .externalReference(externalReference):
                    if let content = externalReference.content {
                        imageResource = content.resource
                    }
                case let .internalReference(internalReference):
                    if let image = internalReference.image {
                        if let imageRepresentation = imageRepresentationLargerThan(image.representations, size: PixelDimensions(width: 1000, height: 800)) {
                            imageResource = imageRepresentation.resource
                        }
                    }
            }
            
            if let imageResource = imageResource {
                imageSignal = .single(context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(imageResource.id)))
                |> mapToSignal { path -> Signal<UIImage, NoError> in
                    if let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]), let image = UIImage(data: data) {
                        return .single(image)
                    } else {
                        return .complete()
                    }
                }
            } else {
                imageSignal = .complete()
            }
    }
    
    if let editedImage {
        imageSignal = .single(editedImage)
    }
    
    let _ = (imageSignal
    |> map { image -> UIImage in
        var croppedImage = UIImage()
        
        let finalCropRect = cropRect ?? defaultWallpaperCropRect(for: image)
        croppedImage = cropWallpaperImage(image, cropRect: finalCropRect, maxSize: CGSize(width: 1440.0, height: 2960.0))
                
        let thumbnailDimensions = finalCropRect.size.fitted(CGSize(width: 320.0, height: 320.0))
        let thumbnailImage = generateScaledImage(image: croppedImage, size: thumbnailDimensions, scale: 1.0)
        
        if let data = croppedImage.jpegData(compressionQuality: 0.8), let thumbnailImage = thumbnailImage, let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.4) {
            let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnailData, synchronous: true)
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnailData, synchronous: true)
            
            let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
            
            let _ = context.sharedContext.accountManager.mediaBox.cachedResourceRepresentation(resource, representation: CachedBlurredWallpaperRepresentation(), complete: true, fetch: true).start()
            
            var intensity: Int32?
            if let brightness {
                intensity = max(0, min(100, Int32(brightness * 100.0)))
            }
            
            Queue.mainQueue().after(0.05) {
                let settings = WallpaperSettings(blur: mode.contains(.blur), motion: mode.contains(.motion), colors: [], intensity: intensity)
                let temporaryWallpaper: TelegramWallpaper = .image([TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailDimensions), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false), TelegramMediaImageRepresentation(dimensions: PixelDimensions(croppedImage.size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)], settings)
                
                context.account.pendingPeerMediaUploadManager.add(peerId: peerId, content: .wallpaper(wallpaper: temporaryWallpaper, forBoth: forBoth))
                
                Queue.mainQueue().after(0.05) {
                    completion()
                }
            }
        }
        return croppedImage
    }).start()
}
