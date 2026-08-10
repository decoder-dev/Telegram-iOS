import Foundation
import UIKit
import AVFoundation
import CoreImage
import Display
import SwiftSignalKit
import TelegramPresentationData

private final class SecureIdScanPreviewView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "PassportUI.SecureIdScan")
    private var latestImage: UIImage?
    private var ocrDisposable: Disposable?
    private var pollTimer: SwiftSignalKit.Timer?
    private var isRunning = false
    
    var finishedWithMRZ: ((SecureIdMRZ) -> Void)?
    
    override init(frame: CGRect) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        super.init(frame: frame)
        self.previewLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(self.previewLayer)
        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
        self.configureSession()
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    deinit {
        self.stop()
    }
    
    private func configureSession() {
        self.session.beginConfiguration()
        self.session.sessionPreset = .photo
        defer { self.session.commitConfiguration() }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              self.session.canAddInput(input),
              self.session.canAddOutput(self.videoOutput) else {
            return
        }
        self.session.addInput(input)
        self.session.addOutput(self.videoOutput)
        if let connection = self.videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
    
    func start() {
        guard !self.isRunning else {
            return
        }
        self.isRunning = true
        self.sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
        self.schedulePoll(after: 0.5)
    }
    
    func stop() {
        self.isRunning = false
        self.pollTimer?.invalidate()
        self.pollTimer = nil
        self.ocrDisposable?.dispose()
        self.ocrDisposable = nil
        self.sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    private func schedulePoll(after interval: Double) {
        self.pollTimer?.invalidate()
        self.pollTimer = SwiftSignalKit.Timer(timeout: interval, repeat: false, completion: { [weak self] in
            self?.pollFrame()
        }, queue: Queue.mainQueue())
        self.pollTimer?.start()
    }
    
    private func pollFrame() {
        guard self.isRunning, let image = self.latestImage else {
            self.schedulePoll(after: 0.45)
            return
        }
        self.ocrDisposable?.dispose()
        self.ocrDisposable = (SecureIdOCR.recognizeData(in: image, shouldBeDriversLicense: false)
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self else {
                return
            }
            if let value {
                self.stop()
                self.finishedWithMRZ?(value)
            } else if self.isRunning {
                self.schedulePoll(after: 0.45)
            }
        })
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = UIImage(sampleBuffer: sampleBuffer) else {
            return
        }
        self.latestImage = image
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.previewLayer.frame = self.bounds
    }
}

private extension UIImage {
    convenience init?(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        self.init(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
}

private final class SecureIdScanControllerNode: ViewControllerTracingNode {
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    private let finished: (SecureIdRecognizedDocumentData?) -> Void
    
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let topFadeView = UIView()
    private let bottomFadeView = UIView()
    private let centerFadeView = UIView()
    private let scanView = SecureIdScanPreviewView()
    private var validLayout: ContainerViewLayout?
    
    init(theme: PresentationTheme, strings: PresentationStrings, finished: @escaping (SecureIdRecognizedDocumentData?) -> Void) {
        self.theme = theme
        self.strings = strings
        self.finished = finished
        super.init()
        
        self.backgroundColor = theme.list.plainBackgroundColor
        
        self.titleLabel.backgroundColor = .clear
        self.titleLabel.font = Font.semibold(23.0)
        self.titleLabel.numberOfLines = 0
        self.titleLabel.lineBreakMode = .byWordWrapping
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.titleLabel.textAlignment = .center
        self.titleLabel.text = strings.Passport_ScanPassport
        self.view.addSubview(self.titleLabel)
        
        self.descriptionLabel.backgroundColor = .clear
        self.descriptionLabel.font = Font.regular(17.0)
        self.descriptionLabel.numberOfLines = 0
        self.descriptionLabel.lineBreakMode = .byWordWrapping
        self.descriptionLabel.textColor = theme.list.itemPrimaryTextColor
        self.descriptionLabel.textAlignment = .center
        self.descriptionLabel.text = strings.Passport_ScanPassportHelp
        self.view.addSubview(self.descriptionLabel)
        
        self.topFadeView.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        self.bottomFadeView.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        self.centerFadeView.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        self.centerFadeView.alpha = 0.0
        self.view.addSubview(self.scanView)
        self.view.addSubview(self.topFadeView)
        self.view.addSubview(self.bottomFadeView)
        self.view.addSubview(self.centerFadeView)
        
        self.scanView.finishedWithMRZ = { [weak self] mrz in
            self?.finish(with: mrz)
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let inset: CGFloat = 30.0
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: bounds.width - inset, height: .greatestFiniteMagnitude))
        let descriptionSize = self.descriptionLabel.sizeThatFits(CGSize(width: bounds.width - inset, height: .greatestFiniteMagnitude))
        let scanHeight = min(475.0, bounds.height - titleSize.height - navigationHeight - 160.0 - layout.intrinsicInsets.bottom)
        let scanFrame = CGRect(x: 0.0, y: navigationHeight, width: bounds.width, height: scanHeight)
        transition.updateFrame(view: self.scanView, frame: scanFrame)
        
        let documentFrameHeight = bounds.width * 0.704
        let documentTopEdge = scanFrame.midY - documentFrameHeight / 2.0
        let documentBottomEdge = scanFrame.midY + documentFrameHeight / 2.0
        transition.updateFrame(view: self.topFadeView, frame: CGRect(x: 0.0, y: scanFrame.minY, width: bounds.width, height: max(0.0, documentTopEdge - scanFrame.minY)))
        transition.updateFrame(view: self.bottomFadeView, frame: CGRect(x: 0.0, y: documentBottomEdge, width: bounds.width, height: max(0.0, scanFrame.maxY - documentBottomEdge)))
        transition.updateFrame(view: self.centerFadeView, frame: CGRect(x: 0.0, y: self.topFadeView.frame.maxY, width: bounds.width, height: max(0.0, self.bottomFadeView.frame.minY - self.topFadeView.frame.maxY)))
        
        let textPanelHeight = bounds.height - navigationHeight - scanHeight - layout.intrinsicInsets.bottom
        let titleY = scanFrame.maxY + (textPanelHeight - titleSize.height - 12.0 - descriptionSize.height) / 2.0
        transition.updateFrame(view: self.titleLabel, frame: CGRect(x: floor((bounds.width - titleSize.width) / 2.0), y: floor(titleY), width: titleSize.width, height: titleSize.height))
        transition.updateFrame(view: self.descriptionLabel, frame: CGRect(x: floor((bounds.width - descriptionSize.width) / 2.0), y: self.titleLabel.frame.maxY + 12.0, width: descriptionSize.width, height: descriptionSize.height))
    }
    
    func start() {
        self.scanView.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    func stop() {
        self.scanView.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func finish(with mrz: SecureIdMRZ) {
        let label = UILabel()
        label.font = Font.regular(17.0)
        label.textColor = .white
        label.numberOfLines = 3
        label.text = mrz.mrz
        label.sizeToFit()
        if let layout = self.validLayout, label.bounds.width > layout.size.width - 20.0 {
            label.font = Font.regular(16.0)
            label.sizeToFit()
        }
        label.center = CGPoint(x: self.bounds.midX, y: self.centerFadeView.frame.maxY - label.bounds.height / 2.0 - 50.0)
        label.alpha = 0.0
        self.view.addSubview(label)
        
        UIView.animate(withDuration: 0.2) {
            label.alpha = 1.0
            self.centerFadeView.alpha = 1.0
        }
        
        Queue.mainQueue().after(1.0) { [weak self] in
            guard let self else {
                return
            }
            self.finished(secureIdRecognizedDocumentData(from: mrz))
        }
    }
}

private final class SecureIdScanController: ViewController {
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    private let finished: (SecureIdRecognizedDocumentData?) -> Void
    private var controllerNode: SecureIdScanControllerNode {
        return self.displayNode as! SecureIdScanControllerNode
    }
    
    init(theme: PresentationTheme, strings: PresentationStrings, finished: @escaping (SecureIdRecognizedDocumentData?) -> Void) {
        self.theme = theme
        self.strings = strings
        self.finished = finished
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: theme), strings: NavigationBarStrings(presentationStrings: strings)))
        self.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .portrait, compactSize: .portrait)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed))
    }
    
    required init(coder aDecoder: NSCoder) {
        preconditionFailure()
    }
    
    override func loadDisplayNode() {
        self.displayNode = SecureIdScanControllerNode(theme: self.theme, strings: self.strings, finished: { [weak self] data in
            self?.finished(data)
            self?.dismiss()
        })
        self.displayNodeDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.controllerNode.start()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.controllerNode.stop()
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.controllerNode.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
    
    @objc private func cancelPressed() {
        self.finished(nil)
        self.dismiss()
    }
}

func secureIdScanController(theme: PresentationTheme, strings: PresentationStrings, finished: @escaping (SecureIdRecognizedDocumentData?) -> Void) -> ViewController {
    return SecureIdScanController(theme: theme, strings: strings, finished: finished)
}
