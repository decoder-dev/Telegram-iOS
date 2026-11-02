import Foundation

struct PermissionContentLayout {
    let contentSize: CGSize
    let illustrationFrame: CGRect
    let titleFrame: CGRect
    let subtitleFrame: CGRect
    let textFrame: CGRect
    let buttonFrame: CGRect
    let privacyFrame: CGRect
    let footerFrame: CGRect
    let showsIllustration: Bool

    init(viewport: CGSize, illustrationSize: CGSize, titleSize: CGSize, subtitleSize: CGSize, textSize: CGSize, buttonSize: CGSize, privacySize: CGSize, footerSize: CGSize) {
        let padding: CGFloat = 24.0
        let subtitleSpacing: CGFloat = subtitleSize.height > 0.0 ? 6.0 : 0.0
        let textSpacing: CGFloat = textSize.height > 0.0 ? 16.0 : 0.0
        let privacySpacing: CGFloat = privacySize.height > 0.0 ? 12.0 : 0.0
        let footerSpacing: CGFloat = footerSize.height > 0.0 ? 24.0 : 0.0
        let textHeight = titleSize.height + subtitleSpacing + subtitleSize.height + textSpacing + textSize.height + 24.0 + buttonSize.height + privacySpacing + privacySize.height + footerSpacing + footerSize.height
        self.showsIllustration = illustrationSize.height > 0.0 && textHeight + illustrationSize.height + 24.0 + padding * 2.0 <= viewport.height
        let illustrationHeight = self.showsIllustration ? illustrationSize.height + 24.0 : 0.0
        let totalHeight = illustrationHeight + textHeight
        self.contentSize = CGSize(width: viewport.width, height: max(viewport.height, totalHeight + padding * 2.0))
        let top = max(padding, floor((self.contentSize.height - totalHeight) * 0.5))

        func frame(_ size: CGSize, y: CGFloat) -> CGRect {
            return CGRect(origin: CGPoint(x: floor((viewport.width - size.width) * 0.5), y: y), size: size)
        }
        self.illustrationFrame = frame(illustrationSize, y: top)
        self.titleFrame = frame(titleSize, y: top + illustrationHeight)
        self.subtitleFrame = frame(subtitleSize, y: self.titleFrame.maxY + subtitleSpacing)
        self.textFrame = frame(textSize, y: self.subtitleFrame.maxY + textSpacing)
        self.buttonFrame = frame(buttonSize, y: self.textFrame.maxY + 24.0)
        self.privacyFrame = frame(privacySize, y: self.buttonFrame.maxY + privacySpacing)
        self.footerFrame = frame(footerSize, y: self.privacyFrame.maxY + footerSpacing)
    }
}
