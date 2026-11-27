import Foundation
import UIKit
import Display
import AsyncDisplayKit
import AccountContext
import TelegramPresentationData
import CoreImage

public final class Ton3DCardScreen: ViewController {
    private let context: AccountContext
    private let balanceAmount: Double
    private let currency: String
    private let walletAddress: String
    private let cardholderName: String

    private var controllerNode: Ton3DCardScreenNode {
        return self.displayNode as! Ton3DCardScreenNode
    }

    public init(
        context: AccountContext,
        balanceAmount: Double,
        currency: String = "TON",
        walletAddress: String,
        cardholderName: String
    ) {
        self.context = context
        self.balanceAmount = balanceAmount
        self.currency = currency
        self.walletAddress = walletAddress.isEmpty ? "UQDx9A_k0M9xL4vQ7zW2yR8tN3pB1c0d9e8f7a6b5c4d3" : walletAddress
        self.cardholderName = cardholderName

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = .White
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        self.displayNode = Ton3DCardScreenNode(
            context: self.context,
            balanceAmount: self.balanceAmount,
            currency: self.currency,
            walletAddress: self.walletAddress,
            cardholderName: self.cardholderName,
            dismiss: { [weak self] in
                self?.dismiss()
            }
        )
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.controllerNode.animateIn()
    }

    override public func dismiss(animated flag: Bool = true, completion: (() -> Void)? = nil) {
        if flag {
            self.controllerNode.animateOut(completion: { [weak self] in
                self?.superDismiss(completion: completion)
            })
        } else {
            super.dismiss(animated: false, completion: completion)
        }
    }

    private func superDismiss(completion: (() -> Void)?) {
        super.dismiss(animated: false, completion: completion)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.controllerNode.containerLayoutUpdated(layout, transition: transition)
    }
}

private final class Ton3DCardScreenNode: ASDisplayNode, UIGestureRecognizerDelegate {
    private let context: AccountContext
    private let balanceAmount: Double
    private let currency: String
    private let walletAddress: String
    private let cardholderName: String
    private let dismiss: () -> Void

    private let dimNode = ASDisplayNode()
    private let cardPerspectiveContainer = UIView()
    private let cardView = UIView()
    private let frontCardView = UIView()
    private let backCardView = UIView()

    private let frontGradientLayer = CAGradientLayer()
    private let glareLayer = CAGradientLayer()
    private let chipView = UIView()
    private let tonLogoView = TonLogoView()
    private let currencyLabel = UILabel()
    private let balanceLabel = UILabel()
    private let usdEstimateLabel = UILabel()
    private let cardholderLabel = UILabel()
    private let addressPreviewLabel = UILabel()
    private let flipHintLabel = UILabel()

    private let backGradientLayer = CAGradientLayer()
    private let magneticStripe = UIView()
    private let qrContainerView = UIView()
    private let qrImageView = UIImageView()
    private let fullAddressLabel = UILabel()
    private let copyAddressButton = UIButton(type: .system)
    private let scanHintLabel = UILabel()

    private let closeButton = UIButton(type: .custom)

    private var isFlipped = false
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(
        context: AccountContext,
        balanceAmount: Double,
        currency: String,
        walletAddress: String,
        cardholderName: String,
        dismiss: @escaping () -> Void
    ) {
        self.context = context
        self.balanceAmount = balanceAmount
        self.currency = currency
        self.walletAddress = walletAddress
        self.cardholderName = cardholderName
        self.dismiss = dismiss

        super.init()

        self.setViewBlock {
            return UIView()
        }
    }

    override func didLoad() {
        super.didLoad()

        self.view.backgroundColor = .clear

        self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.75)
        self.dimNode.alpha = 0.0
        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        self.addSubnode(self.dimNode)

        self.view.addSubview(self.cardPerspectiveContainer)
        self.cardPerspectiveContainer.addSubview(self.cardView)

        self.setupFrontCard()
        self.setupBackCard()

        self.cardView.addSubview(self.frontCardView)
        self.cardView.addSubview(self.backCardView)
        self.backCardView.isHidden = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        pan.delegate = self
        self.cardView.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleCardTap))
        tap.delegate = self
        self.cardView.addGestureRecognizer(tap)

        self.closeButton.setImage(generateCloseIcon(), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.7)
        self.closeButton.backgroundColor = UIColor(white: 0.15, alpha: 0.8)
        self.closeButton.layer.cornerRadius = 18.0
        self.closeButton.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
        self.view.addSubview(self.closeButton)
    }

    private func setupFrontCard() {
        self.frontCardView.backgroundColor = UIColor(red: 14/255.0, green: 18/255.0, blue: 24/255.0, alpha: 1.0)
        self.frontCardView.layer.cornerRadius = 20.0
        self.frontCardView.layer.masksToBounds = true
        self.frontCardView.layer.borderColor = UIColor(red: 0/255.0, green: 152/255.0, blue: 234/255.0, alpha: 0.35).cgColor
        self.frontCardView.layer.borderWidth = 1.0

        self.frontGradientLayer.colors = [
            UIColor(red: 22/255.0, green: 30/255.0, blue: 40/255.0, alpha: 1.0).cgColor,
            UIColor(red: 10/255.0, green: 13/255.0, blue: 18/255.0, alpha: 1.0).cgColor
        ]
        self.frontGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.frontGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.frontCardView.layer.insertSublayer(self.frontGradientLayer, at: 0)

        self.glareLayer.colors = [
            UIColor(white: 1.0, alpha: 0.0).cgColor,
            UIColor(white: 1.0, alpha: 0.16).cgColor,
            UIColor(white: 1.0, alpha: 0.0).cgColor
        ]
        self.glareLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.glareLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.frontCardView.layer.insertSublayer(self.glareLayer, at: 1)

        self.frontCardView.addSubview(self.tonLogoView)

        self.currencyLabel.text = self.currency.uppercased()
        self.currencyLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .bold)
        self.currencyLabel.textColor = UIColor(red: 0/255.0, green: 172/255.0, blue: 255/255.0, alpha: 1.0)
        self.frontCardView.addSubview(self.currencyLabel)

        self.flipHintLabel.text = "3D • Нажмите для QR ↷"
        self.flipHintLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        self.flipHintLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        self.flipHintLabel.textAlignment = .right
        self.frontCardView.addSubview(self.flipHintLabel)

        let formattedBalance: String
        if self.balanceAmount >= 1_000_000 {
            formattedBalance = String(format: "%.0f", self.balanceAmount)
        } else if self.balanceAmount.truncatingRemainder(dividingBy: 1) == 0 {
            formattedBalance = String(format: "%.0f", self.balanceAmount)
        } else {
            formattedBalance = String(format: "%.2f", self.balanceAmount)
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = " "
        let formattedString = numberFormatter.string(from: NSNumber(value: self.balanceAmount)) ?? formattedBalance

        self.balanceLabel.text = "\(formattedString) \(self.currency)"
        self.balanceLabel.font = UIFont.systemFont(ofSize: 26.0, weight: .bold)
        self.balanceLabel.textColor = .white
        self.frontCardView.addSubview(self.balanceLabel)

        let usdRate = self.currency == "TON" ? 5.20 : 0.015
        let usdTotal = self.balanceAmount * usdRate
        let usdString = numberFormatter.string(from: NSNumber(value: usdTotal)) ?? String(format: "%.2f", usdTotal)
        self.usdEstimateLabel.text = "≈ $\(usdString) USD"
        self.usdEstimateLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.usdEstimateLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.frontCardView.addSubview(self.usdEstimateLabel)

        self.setupChipView()
        self.frontCardView.addSubview(self.chipView)

        self.cardholderLabel.text = self.cardholderName.isEmpty ? "TON HOLDER" : self.cardholderName.uppercased()
        self.cardholderLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        self.cardholderLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.frontCardView.addSubview(self.cardholderLabel)

        let address = self.walletAddress
        self.addressPreviewLabel.text = "\(address.prefix(6))...\(address.suffix(6))"
        self.addressPreviewLabel.font = UIFont.monospacedSystemFont(ofSize: 11.0, weight: .medium)
        self.addressPreviewLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        self.addressPreviewLabel.textAlignment = .right
        self.frontCardView.addSubview(self.addressPreviewLabel)
    }

    private func setupChipView() {
        self.chipView.backgroundColor = UIColor(red: 212/255.0, green: 175/255.0, blue: 55/255.0, alpha: 0.85)
        self.chipView.layer.cornerRadius = 6.0
        self.chipView.layer.borderWidth = 1.0
        self.chipView.layer.borderColor = UIColor(red: 255/255.0, green: 223/255.0, blue: 115/255.0, alpha: 0.6).cgColor
        self.chipView.clipsToBounds = true

        let line1 = UIView()
        line1.backgroundColor = UIColor(white: 0.0, alpha: 0.25)
        self.chipView.addSubview(line1)
        line1.frame = CGRect(x: 14.0, y: 0.0, width: 1.0, height: 24.0)

        let line2 = UIView()
        line2.backgroundColor = UIColor(white: 0.0, alpha: 0.25)
        self.chipView.addSubview(line2)
        line2.frame = CGRect(x: 0.0, y: 12.0, width: 32.0, height: 1.0)
    }

    private func setupBackCard() {
        self.backCardView.backgroundColor = UIColor(red: 12/255.0, green: 15/255.0, blue: 20/255.0, alpha: 1.0)
        self.backCardView.layer.cornerRadius = 20.0
        self.backCardView.layer.masksToBounds = true
        self.backCardView.layer.borderColor = UIColor(red: 0/255.0, green: 152/255.0, blue: 234/255.0, alpha: 0.35).cgColor
        self.backCardView.layer.borderWidth = 1.0

        self.backGradientLayer.colors = [
            UIColor(red: 18/255.0, green: 24/255.0, blue: 32/255.0, alpha: 1.0).cgColor,
            UIColor(red: 8/255.0, green: 11/255.0, blue: 15/255.0, alpha: 1.0).cgColor
        ]
        self.backGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.backGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.backCardView.layer.insertSublayer(self.backGradientLayer, at: 0)

        self.magneticStripe.backgroundColor = UIColor(red: 20/255.0, green: 22/255.0, blue: 26/255.0, alpha: 1.0)
        self.backCardView.addSubview(self.magneticStripe)

        self.qrContainerView.backgroundColor = .white
        self.qrContainerView.layer.cornerRadius = 14.0
        self.qrContainerView.layer.masksToBounds = true
        self.backCardView.addSubview(self.qrContainerView)

        self.qrImageView.contentMode = .scaleAspectFit
        self.qrImageView.image = self.generateQRCode(from: self.walletAddress, size: CGSize(width: 90.0, height: 90.0))
        self.qrContainerView.addSubview(self.qrImageView)

        self.fullAddressLabel.text = self.walletAddress
        self.fullAddressLabel.font = UIFont.monospacedSystemFont(ofSize: 10.0, weight: .regular)
        self.fullAddressLabel.textColor = UIColor(white: 1.0, alpha: 0.75)
        self.fullAddressLabel.textAlignment = .center
        self.fullAddressLabel.lineBreakMode = .byTruncatingMiddle
        self.backCardView.addSubview(self.fullAddressLabel)

        self.copyAddressButton.setTitle("Скопировать адрес", for: .normal)
        self.copyAddressButton.titleLabel?.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.copyAddressButton.setTitleColor(.white, for: .normal)
        self.copyAddressButton.backgroundColor = UIColor(red: 0/255.0, green: 152/255.0, blue: 234/255.0, alpha: 1.0)
        self.copyAddressButton.layer.cornerRadius = 14.0
        self.copyAddressButton.addTarget(self, action: #selector(self.copyAddressTapped), for: .touchUpInside)
        self.backCardView.addSubview(self.copyAddressButton)

        self.scanHintLabel.text = "Нажмите в любое место, чтобы перевернуть обратно"
        self.scanHintLabel.font = UIFont.systemFont(ofSize: 10.0, weight: .regular)
        self.scanHintLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        self.scanHintLabel.textAlignment = .center
        self.backCardView.addSubview(self.scanHintLabel)
    }

    @objc private func handleCardTap() {
        self.flipCard()
    }

    private func flipCard() {
        self.isFlipped = !self.isFlipped
        HapticFeedback().impact(.light)

        let transitionOptions: UIView.AnimationOptions = self.isFlipped ? [.transitionFlipFromRight, .curveEaseInOut] : [.transitionFlipFromLeft, .curveEaseInOut]
        UIView.transition(with: self.cardView, duration: 0.5, options: transitionOptions, animations: {
            self.frontCardView.isHidden = self.isFlipped
            self.backCardView.isHidden = !self.isFlipped
        }, completion: nil)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !self.isFlipped else { return }

        let translation = gesture.translation(in: self.cardView)
        let maxAngle: CGFloat = 0.35

        switch gesture.state {
        case .changed:
            let rotY = min(max(translation.x / 140.0 * maxAngle, -maxAngle), maxAngle)
            let rotX = min(max(-translation.y / 140.0 * maxAngle, -maxAngle), maxAngle)

            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 800.0
            transform = CATransform3DRotate(transform, rotX, 1.0, 0.0, 0.0)
            transform = CATransform3DRotate(transform, rotY, 0.0, 1.0, 0.0)
            self.cardView.layer.transform = transform

            let glareShiftX = translation.x / 100.0
            let glareShiftY = translation.y / 100.0
            self.glareLayer.transform = CATransform3DMakeTranslation(glareShiftX * 25.0, glareShiftY * 25.0, 0.0)

        case .ended, .cancelled:
            UIView.animate(withDuration: 0.6, delay: 0.0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.cardView.layer.transform = CATransform3DIdentity
                self.glareLayer.transform = CATransform3DIdentity
            }, completion: nil)

        default:
            break
        }
    }

    @objc private func copyAddressTapped() {
        UIPasteboard.general.string = self.walletAddress
        HapticFeedback().success()

        self.copyAddressButton.setTitle("✓ Скопировано!", for: .normal)
        self.copyAddressButton.backgroundColor = UIColor(red: 46/255.0, green: 189/255.0, blue: 89/255.0, alpha: 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            self.copyAddressButton.setTitle("Скопировать адрес", for: .normal)
            self.copyAddressButton.backgroundColor = UIColor(red: 0/255.0, green: 152/255.0, blue: 234/255.0, alpha: 1.0)
        }
    }

    @objc private func dimTapped() {
        self.dismiss()
    }

    @objc private func closeTapped() {
        self.dismiss()
    }

    func animateIn() {
        self.dimNode.alpha = 0.0
        self.cardView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85).translatedBy(x: 0.0, y: 40.0)
        self.cardView.alpha = 0.0

        UIView.animate(withDuration: 0.25, animations: {
            self.dimNode.alpha = 1.0
        })

        UIView.animate(withDuration: 0.55, delay: 0.05, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.6, options: [], animations: {
            self.cardView.transform = .identity
            self.cardView.alpha = 1.0
        }, completion: nil)
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2, animations: {
            self.dimNode.alpha = 0.0
            self.cardView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9).translatedBy(x: 0.0, y: 30.0)
            self.cardView.alpha = 0.0
            self.closeButton.alpha = 0.0
        }, completion: { _ in
            completion()
        })
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(node: self.dimNode, frame: CGRect(origin: .zero, size: layout.size))

        let cardWidth = min(340.0, layout.size.width - 36.0)
        let cardHeight = round(cardWidth * 0.628)

        let cardX = floor((layout.size.width - cardWidth) / 2.0)
        let cardY = floor((layout.size.height - cardHeight) / 2.0)

        self.cardPerspectiveContainer.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        self.cardView.frame = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        self.frontCardView.frame = self.cardView.bounds
        self.backCardView.frame = self.cardView.bounds

        self.frontGradientLayer.frame = self.frontCardView.bounds
        self.glareLayer.frame = CGRect(x: -cardWidth * 0.5, y: -cardHeight * 0.5, width: cardWidth * 2.0, height: cardHeight * 2.0)
        self.backGradientLayer.frame = self.backCardView.bounds

        self.tonLogoView.frame = CGRect(x: 18.0, y: 16.0, width: 26.0, height: 26.0)
        self.currencyLabel.frame = CGRect(x: 48.0, y: 20.0, width: 60.0, height: 18.0)
        self.flipHintLabel.frame = CGRect(x: cardWidth - 160.0, y: 20.0, width: 142.0, height: 16.0)

        self.balanceLabel.frame = CGRect(x: 18.0, y: 64.0, width: cardWidth - 36.0, height: 32.0)
        self.usdEstimateLabel.frame = CGRect(x: 18.0, y: 98.0, width: cardWidth - 36.0, height: 18.0)

        self.chipView.frame = CGRect(x: 18.0, y: cardHeight - 56.0, width: 32.0, height: 24.0)
        self.cardholderLabel.frame = CGRect(x: 58.0, y: cardHeight - 52.0, width: cardWidth - 180.0, height: 16.0)
        self.addressPreviewLabel.frame = CGRect(x: cardWidth - 120.0, y: cardHeight - 52.0, width: 102.0, height: 16.0)

        self.magneticStripe.frame = CGRect(x: 0.0, y: 20.0, width: cardWidth, height: 32.0)

        let qrSize: CGFloat = 88.0
        self.qrContainerView.frame = CGRect(x: floor((cardWidth - qrSize) / 2.0), y: 62.0, width: qrSize, height: qrSize)
        self.qrImageView.frame = CGRect(x: 4.0, y: 4.0, width: qrSize - 8.0, height: qrSize - 8.0)

        self.fullAddressLabel.frame = CGRect(x: 16.0, y: 156.0, width: cardWidth - 32.0, height: 14.0)

        let buttonWidth: CGFloat = 160.0
        let buttonHeight: CGFloat = 28.0
        self.copyAddressButton.frame = CGRect(x: floor((cardWidth - buttonWidth) / 2.0), y: 174.0, width: buttonWidth, height: buttonHeight)

        self.scanHintLabel.frame = CGRect(x: 16.0, y: cardHeight - 24.0, width: cardWidth - 32.0, height: 14.0)

        let closeY = max(44.0, layout.insets(options: .statusBar).top + 10.0)
        self.closeButton.frame = CGRect(x: layout.size.width - 48.0, y: closeY, width: 36.0, height: 36.0)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return !(touch.view is UIButton)
    }

    private func generateQRCode(from string: String, size: CGSize) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let scaleX = size.width / outputImage.extent.size.width
        let scaleY = size.height / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = Self.ciContext.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private final class TonLogoView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let width = rect.width
        let height = rect.height

        let path = UIBezierPath()
        path.move(to: CGPoint(x: width * 0.5, y: 0.0))
        path.addLine(to: CGPoint(x: width, y: height * 0.32))
        path.addLine(to: CGPoint(x: width * 0.5, y: height))
        path.addLine(to: CGPoint(x: 0.0, y: height * 0.32))
        path.close()

        context.saveGState()
        path.addClip()

        let colors = [
            UIColor(red: 0/255.0, green: 152/255.0, blue: 234/255.0, alpha: 1.0).cgColor,
            UIColor(red: 0/255.0, green: 194/255.0, blue: 255/255.0, alpha: 1.0).cgColor
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: width, y: height), options: [])
        }
        context.restoreGState()

        let facetPath = UIBezierPath()
        facetPath.move(to: CGPoint(x: width * 0.5, y: 0.0))
        facetPath.addLine(to: CGPoint(x: width * 0.5, y: height))
        facetPath.move(to: CGPoint(x: 0.0, y: height * 0.32))
        facetPath.addLine(to: CGPoint(x: width * 0.5, y: height * 0.44))
        facetPath.addLine(to: CGPoint(x: width, y: height * 0.32))

        UIColor(white: 1.0, alpha: 0.45).setStroke()
        facetPath.lineWidth = 1.0
        facetPath.stroke()
    }
}

private func generateCloseIcon() -> UIImage? {
    let size = CGSize(width: 14.0, height: 14.0)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    guard let context = UIGraphicsGetCurrentContext() else {
        UIGraphicsEndImageContext()
        return nil
    }

    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(2.0)
    context.setLineCap(.round)

    context.move(to: CGPoint(x: 2.0, y: 2.0))
    context.addLine(to: CGPoint(x: 12.0, y: 12.0))
    context.strokePath()

    context.move(to: CGPoint(x: 12.0, y: 2.0))
    context.addLine(to: CGPoint(x: 2.0, y: 12.0))
    context.strokePath()

    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
}
