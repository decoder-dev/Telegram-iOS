import Foundation
import TelegramCore
import UIKit
import UniformTypeIdentifiers
import Display
import TelegramPresentationData
import LegacyUI

private class DocumentPickerViewController: UIDocumentPickerViewController {
    var forceDarkTheme = false
    var didDisappear: (() -> Void)?
    // UIKit's delegate is weak. Keep it alive through dismissal, which can precede
    // delivery of the selected URLs and otherwise remove the legacy wrapper first.
    var retainedPickerDelegate: UIDocumentPickerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *), self.forceDarkTheme {
            self.overrideUserInterfaceStyle = .dark
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.didDisappear?()
    }
}

private final class LegacyICloudFileController: LegacyController, UIDocumentPickerDelegate {
    let completion: ([URL]) -> Void
    private var didComplete = false

    private func complete(_ urls: [URL], source: String) {
        guard !self.didComplete else { return }
        self.didComplete = true
        Logger.shared.log("FilesPicker", "Selection completed via \(source) (count: \(urls.count))")
        self.completion(urls)
    }
    
    init(presentation: LegacyControllerPresentation, theme: PresentationTheme?, completion: @escaping ([URL]) -> Void) {
        self.completion = completion
        
        super.init(presentation: presentation, theme: theme)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.complete([], source: "cancel")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.complete(urls, source: "didPickDocumentsAt")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        self.complete([url], source: "didPickDocumentAt")
    }
}

public enum LegacyICloudFilePickerMode {
    case `default`
    case `import`
    case `export`
    
    /// iOS 14 replaced `UIDocumentPickerMode` with an `asCopy` flag on the opening/exporting
    /// initializers: the old `.open` is `asCopy: false`, while `.import` and `.exportToService`
    /// are both `asCopy: true`.
    var asCopy: Bool {
        switch self {
        case .default:
            return false
        case .import, .export:
            return true
        }
    }
}

public func legacyICloudFilePicker(theme: PresentationTheme, mode: LegacyICloudFilePickerMode = .default, hasMultiselection: Bool = false, url: URL? = nil, documentTypes: [String] = ["public.item"], forceDarkTheme: Bool = false, dismissed: @escaping () -> Void = {}, completion: @escaping ([URL]) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?
    let legacyController = LegacyICloudFileController(presentation: .modal(animateIn: true), theme: theme, completion: { urls in
        dismissImpl?()
        completion(urls)
    })
    legacyController.statusBar.statusBarStyle = .Black
    
    let controller: DocumentPickerViewController
    // Exporting a missing file raises a UIKit exception.
    if case .export = mode, let url, FileManager.default.fileExists(atPath: url.path) {
        controller = DocumentPickerViewController(forExporting: [url], asCopy: true)
    } else {
        // The old `documentTypes:` initializer took raw UTI strings, so identifiers the system does
        // not know (e.g. "org.xiph.flac", which the app does not declare) must not be dropped --
        // dropping them would silently make those files unselectable, and dropping all of them would
        // silently widen the picker to every file.
        let contentTypes = documentTypes.map { UTType($0) ?? UTType(importedAs: $0) }
        controller = DocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: mode.asCopy)
    }
    controller.forceDarkTheme = forceDarkTheme || theme.overallDarkAppearance
    controller.didDisappear = {
        dismissImpl?()
    }
    controller.delegate = legacyController
    controller.retainedPickerDelegate = legacyController
    if #available(iOSApplicationExtension 11.0, iOS 11.0, *), hasMultiselection {
        controller.allowsMultipleSelection = true
    }
    
    legacyController.presentationCompleted = { [weak legacyController] in
        if let legacyController = legacyController {
            if let window = legacyController.view.window {
                controller.popoverPresentationController?.sourceView = window
                controller.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
                window.rootViewController?.present(controller, animated: true)
                legacyController.presentationCompleted = nil
            }
        }
    }
    
    dismissImpl = { [weak legacyController] in
        if let legacyController = legacyController {
            legacyController.dismiss()
        }
        dismissed()
    }
    legacyController.bind(controller: UIViewController())
    return legacyController
}
