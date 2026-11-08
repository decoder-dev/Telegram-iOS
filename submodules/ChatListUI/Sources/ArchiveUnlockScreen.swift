import Foundation
import UIKit
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

/// The full-screen lock for the protected Archive, Saved Messages and hidden accounts (scenes 27 and 53).
///
/// The screen only collects the password. Every decision (matching, the Keychain attempt limit and cooldown, the owner
/// reset, the single-flight prompt) stays in `presentArchivePasswordAlert`, which drives it through `submit`, `cancel`
/// and `resetOwner` and answers with `showMessage` and `close`. Leaving the screen any other way than `close` (the Close
/// button, or anything that dismisses it) reports `cancel` exactly once, so a caller always gets a terminal result.
final class ArchiveUnlockScreen: UIViewController, UITextFieldDelegate {
    enum Subject {
        case archive
        case savedMessages
        case hiddenAccount
    }

    var submit: ((String) -> Void)?
    var cancel: (() -> Void)?
    var resetOwner: (() -> Void)?

    private let subject: Subject
    private let subtitleText: String
    private let confirmTitle: String
    private let resetTitle: String?
    private var presentationData: PresentationData
    private let presentationDataDisposable = MetaDisposable()

    private var closedByOwner = false
    private var reportedCancel = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let navigationTitleLabel = UILabel()
    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let fieldBackground = UIView()
    private let passwordField = UITextField()
    private let messageLabel = UILabel()
    private let unlockButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let footerLabel = UILabel()
    private var messageIsError = false

    init(context: AccountContext, subject: Subject, message: String?, confirmTitle: String, resetTitle: String?) {
        self.subject = subject
        self.subtitleText = message ?? ArchiveLockLocalizedString.lockedSubtitle
        self.confirmTitle = confirmTitle
        self.resetTitle = resetTitle
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .fullScreen
        self.modalTransitionStyle = .coverVertical

        self.presentationDataDisposable.set((context.sharedContext.presentationData
        |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            if self.isViewLoaded {
                self.applyTheme()
            }
        }))
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    deinit {
        self.presentationDataDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
        // Released without `close` and without a Close tap: whoever dismissed it still owes the caller a result.
        if !self.closedByOwner && !self.reportedCancel, let cancel = self.cancel {
            DispatchQueue.main.async {
                cancel()
            }
        }
    }

    private var screenTitle: String {
        switch self.subject {
        case .archive:
            return ArchiveLockLocalizedString.lockedArchiveTitle
        case .savedMessages:
            return ArchiveLockLocalizedString.lockedSavedTitle
        case .hiddenAccount:
            return ArchiveLockLocalizedString.lockedHiddenTitle
        }
    }

    private var navigationTitle: String {
        switch self.subject {
        case .archive, .hiddenAccount:
            return ArchiveLockLocalizedString.screenTitle
        case .savedMessages:
            return ArchiveLockLocalizedString.savedNavigationTitle
        }
    }

    private var symbolName: String {
        switch self.subject {
        case .archive:
            return "archivebox.fill"
        case .savedMessages:
            return "bookmark.fill"
        case .hiddenAccount:
            return "person.crop.circle.badge.questionmark"
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return self.presentationData.theme.overallDarkAppearance ? .lightContent : .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.closeButton.setTitle(ArchiveLockLocalizedString.close, for: .normal)
        self.closeButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.closeButton.titleLabel?.adjustsFontForContentSizeCategory = true
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.closeButton.translatesAutoresizingMaskIntoConstraints = false

        self.navigationTitleLabel.text = self.navigationTitle
        self.navigationTitleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        self.navigationTitleLabel.adjustsFontForContentSizeCategory = true
        self.navigationTitleLabel.textAlignment = .center
        self.navigationTitleLabel.accessibilityTraits = .header
        self.navigationTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false

        self.contentStack.axis = .vertical
        self.contentStack.alignment = .fill
        self.contentStack.spacing = 12.0
        self.contentStack.translatesAutoresizingMaskIntoConstraints = false

        self.iconBackground.layer.cornerRadius = 40.0
        self.iconBackground.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.image = UIImage(systemName: self.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 34.0, weight: .semibold))
        self.iconView.contentMode = .center
        self.iconView.isAccessibilityElement = false
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconBackground.addSubview(self.iconView)
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(self.iconBackground)

        self.titleLabel.text = self.screenTitle
        self.titleLabel.font = UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        self.titleLabel.adjustsFontForContentSizeCategory = true
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.titleLabel.accessibilityTraits = .header

        self.subtitleLabel.text = self.subtitleText
        self.subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.subtitleLabel.adjustsFontForContentSizeCategory = true
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 0

        self.fieldBackground.layer.cornerRadius = 12.0
        self.fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        self.passwordField.isSecureTextEntry = true
        self.passwordField.textContentType = .password
        self.passwordField.autocorrectionType = .no
        self.passwordField.autocapitalizationType = .none
        self.passwordField.spellCheckingType = .no
        self.passwordField.returnKeyType = .done
        self.passwordField.enablesReturnKeyAutomatically = true
        self.passwordField.font = UIFont.preferredFont(forTextStyle: .body)
        self.passwordField.adjustsFontForContentSizeCategory = true
        self.passwordField.accessibilityLabel = ArchiveLockLocalizedString.passwordPlaceholder
        self.passwordField.delegate = self
        self.passwordField.addTarget(self, action: #selector(self.textChanged), for: .editingChanged)
        self.passwordField.translatesAutoresizingMaskIntoConstraints = false
        self.fieldBackground.addSubview(self.passwordField)

        self.messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.messageLabel.adjustsFontForContentSizeCategory = true
        self.messageLabel.textAlignment = .center
        self.messageLabel.numberOfLines = 0
        // `showMessage` may have run before the view loaded (a cooldown already standing).
        self.messageLabel.isHidden = (self.messageLabel.text ?? "").isEmpty

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.title = self.confirmTitle
        self.unlockButton.configuration = configuration
        self.unlockButton.addTarget(self, action: #selector(self.unlockPressed), for: .touchUpInside)
        self.unlockButton.translatesAutoresizingMaskIntoConstraints = false

        if let resetTitle = self.resetTitle {
            self.resetButton.setTitle(resetTitle, for: .normal)
            self.resetButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
            self.resetButton.titleLabel?.adjustsFontForContentSizeCategory = true
            self.resetButton.titleLabel?.numberOfLines = 0
            self.resetButton.titleLabel?.textAlignment = .center
            self.resetButton.addTarget(self, action: #selector(self.resetPressed), for: .touchUpInside)
        } else {
            self.resetButton.isHidden = true
        }

        self.footerLabel.text = ArchiveLockLocalizedString.lockedFooter
        self.footerLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        self.footerLabel.adjustsFontForContentSizeCategory = true
        self.footerLabel.textAlignment = .center
        self.footerLabel.numberOfLines = 0

        self.contentStack.addArrangedSubview(iconContainer)
        self.contentStack.setCustomSpacing(20.0, after: iconContainer)
        self.contentStack.addArrangedSubview(self.titleLabel)
        self.contentStack.setCustomSpacing(6.0, after: self.titleLabel)
        self.contentStack.addArrangedSubview(self.subtitleLabel)
        self.contentStack.setCustomSpacing(28.0, after: self.subtitleLabel)
        self.contentStack.addArrangedSubview(self.fieldBackground)
        self.contentStack.addArrangedSubview(self.messageLabel)
        self.contentStack.setCustomSpacing(20.0, after: self.messageLabel)
        self.contentStack.addArrangedSubview(self.unlockButton)
        self.contentStack.addArrangedSubview(self.resetButton)
        self.contentStack.setCustomSpacing(24.0, after: self.resetButton)
        self.contentStack.addArrangedSubview(self.footerLabel)

        self.view.addSubview(self.scrollView)
        self.view.addSubview(self.closeButton)
        self.view.addSubview(self.navigationTitleLabel)
        self.scrollView.addSubview(self.contentStack)

        let safeArea = self.view.safeAreaLayoutGuide
        let readable = self.view.readableContentGuide
        // Centred while it fits; a long title (large text, a long translation) gives way and truncates instead of running
        // under the Close button or off the screen.
        let titleCenter = self.navigationTitleLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        titleCenter.priority = .defaultHigh
        self.navigationTitleLabel.lineBreakMode = .byTruncatingTail
        self.navigationTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            self.closeButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16.0),
            self.closeButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 6.0),
            self.closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0),
            titleCenter,
            self.navigationTitleLabel.centerYAnchor.constraint(equalTo: self.closeButton.centerYAnchor),
            self.navigationTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: self.closeButton.trailingAnchor, constant: 8.0),
            self.navigationTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -16.0),

            self.scrollView.topAnchor.constraint(equalTo: self.closeButton.bottomAnchor, constant: 4.0),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            self.contentStack.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 32.0),
            self.contentStack.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -24.0),
            self.contentStack.leadingAnchor.constraint(equalTo: readable.leadingAnchor, constant: 8.0),
            self.contentStack.trailingAnchor.constraint(equalTo: readable.trailingAnchor, constant: -8.0),

            iconContainer.heightAnchor.constraint(equalToConstant: 80.0),
            self.iconBackground.widthAnchor.constraint(equalToConstant: 80.0),
            self.iconBackground.heightAnchor.constraint(equalToConstant: 80.0),
            self.iconBackground.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            self.iconBackground.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            self.iconView.centerXAnchor.constraint(equalTo: self.iconBackground.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.iconBackground.centerYAnchor),

            self.fieldBackground.heightAnchor.constraint(greaterThanOrEqualToConstant: 50.0),
            self.passwordField.leadingAnchor.constraint(equalTo: self.fieldBackground.leadingAnchor, constant: 16.0),
            self.passwordField.trailingAnchor.constraint(equalTo: self.fieldBackground.trailingAnchor, constant: -16.0),
            self.passwordField.topAnchor.constraint(equalTo: self.fieldBackground.topAnchor, constant: 8.0),
            self.passwordField.bottomAnchor.constraint(equalTo: self.fieldBackground.bottomAnchor, constant: -8.0),
            self.unlockButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50.0),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardFrameChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardFrameChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        self.applyTheme()
        self.updateUnlockEnabled()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.passwordField.becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.presentingViewController == nil || self.isBeingDismissed {
            self.reportCancelIfNeeded()
        }
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        self.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.view.backgroundColor = theme.list.blocksBackgroundColor
        self.view.tintColor = theme.list.itemAccentColor
        self.navigationTitleLabel.textColor = theme.list.itemPrimaryTextColor
        self.closeButton.tintColor = theme.list.itemAccentColor
        self.iconBackground.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.15)
        self.iconView.tintColor = theme.list.itemAccentColor
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.subtitleLabel.textColor = theme.list.itemSecondaryTextColor
        self.fieldBackground.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.passwordField.textColor = theme.list.itemPrimaryTextColor
        self.passwordField.tintColor = theme.list.itemAccentColor
        self.passwordField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.passwordField.attributedPlaceholder = NSAttributedString(string: ArchiveLockLocalizedString.passwordPlaceholder, attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor])
        self.messageLabel.textColor = self.messageIsError ? theme.list.itemDestructiveColor : theme.list.itemSecondaryTextColor
        if var configuration = self.unlockButton.configuration {
            configuration.baseBackgroundColor = theme.list.itemCheckColors.fillColor
            configuration.baseForegroundColor = theme.list.itemCheckColors.foregroundColor
            self.unlockButton.configuration = configuration
        }
        self.resetButton.tintColor = theme.list.itemDestructiveColor
        self.footerLabel.textColor = theme.list.freeTextColor
        self.setNeedsStatusBarAppearanceUpdate()
    }

    private func updateUnlockEnabled() {
        self.unlockButton.isEnabled = !(self.passwordField.text ?? "").isEmpty
    }

    /// Shows a message under the field (an incorrect password or the cooldown) and clears the field for the next try.
    func showMessage(_ text: String, isError: Bool) {
        self.messageIsError = isError
        self.messageLabel.text = text
        self.messageLabel.isHidden = false
        self.messageLabel.textColor = isError ? self.presentationData.theme.list.itemDestructiveColor : self.presentationData.theme.list.itemSecondaryTextColor
        self.passwordField.text = ""
        self.updateUnlockEnabled()
        UIAccessibility.post(notification: .announcement, argument: text)
        if isError {
            // A wrong password answers with the system's error haptic, as the lock screen's passcode does.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        if isError, !UIAccessibility.isReduceMotionEnabled {
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0.0, -10.0, 10.0, -6.0, 6.0, -2.0, 0.0]
            animation.duration = 0.4
            self.fieldBackground.layer.add(animation, forKey: "shake")
        }
    }

    /// Dismisses the screen after the caller has decided the outcome; reports nothing.
    func close() {
        self.closedByOwner = true
        self.passwordField.resignFirstResponder()
        if self.presentingViewController != nil {
            self.dismiss(animated: true)
        }
    }

    private func reportCancelIfNeeded() {
        guard !self.closedByOwner, !self.reportedCancel else {
            return
        }
        self.reportedCancel = true
        self.cancel?()
    }

    @objc private func closePressed() {
        self.passwordField.resignFirstResponder()
        self.reportCancelIfNeeded()
        self.closedByOwner = true
        self.dismiss(animated: true)
    }

    @objc private func unlockPressed() {
        let text = self.passwordField.text ?? ""
        guard !text.isEmpty else {
            return
        }
        self.submit?(text)
    }

    @objc private func resetPressed() {
        self.passwordField.resignFirstResponder()
        self.resetOwner?()
    }

    @objc private func textChanged() {
        self.updateUnlockEnabled()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.unlockPressed()
        return false
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        let keyboardFrame = self.view.convert(frameValue.cgRectValue, from: nil)
        var inset = max(0.0, self.view.bounds.maxY - keyboardFrame.minY - self.view.safeAreaInsets.bottom)
        if notification.name == UIResponder.keyboardWillHideNotification {
            inset = 0.0
        }
        self.scrollView.contentInset.bottom = inset
        self.scrollView.verticalScrollIndicatorInsets.bottom = inset
        if inset > 0.0 {
            let target = self.scrollView.convert(self.unlockButton.frame, from: self.contentStack)
            self.scrollView.scrollRectToVisible(target.insetBy(dx: 0.0, dy: -12.0), animated: true)
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = self.fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0.0)
    }
}

/// Presents the lock above whatever is on screen, like the password alert it replaced.
func presentArchiveUnlockScreen(context: AccountContext, screen: ArchiveUnlockScreen, onUnavailableHost: @escaping () -> Void) {
    if let host = context.sharedContext.applicationBindings.getTopWindow()?.rootViewController {
        var presenter = host
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(screen, animated: true)
    } else {
        onUnavailableHost()
    }
}
