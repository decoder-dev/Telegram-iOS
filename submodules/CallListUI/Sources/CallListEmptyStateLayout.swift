import Foundation

struct CallListEmptyStateLayout {
    let contentSize: CGSize
    let illustrationFrame: CGRect
    let textFrame: CGRect
    let buttonFrame: CGRect
    let showsIllustration: Bool

    init(viewport: CGSize, illustrationSize: CGSize, textSize: CGSize, buttonContentSize: CGSize) {
        let padding: CGFloat = 24.0
        let textSpacing: CGFloat = 23.0
        let illustrationSpacing: CGFloat = 13.0
        let buttonSize = CGSize(width: max(44.0, buttonContentSize.width), height: max(44.0, buttonContentSize.height + 16.0))
        let textAndButtonHeight = textSize.height + textSpacing + buttonSize.height
        self.showsIllustration = illustrationSize.height + illustrationSpacing + textAndButtonHeight + padding * 2.0 <= viewport.height
        let illustrationHeight = self.showsIllustration ? illustrationSize.height + illustrationSpacing : 0.0
        let totalHeight = illustrationHeight + textAndButtonHeight
        self.contentSize = CGSize(width: viewport.width, height: max(viewport.height, totalHeight + padding * 2.0))
        let top = max(padding, floor((self.contentSize.height - totalHeight) * 0.5))
        self.illustrationFrame = CGRect(origin: CGPoint(x: floor((viewport.width - illustrationSize.width) * 0.5), y: top), size: illustrationSize)
        self.textFrame = CGRect(origin: CGPoint(x: floor((viewport.width - textSize.width) * 0.5), y: top + illustrationHeight), size: textSize)
        self.buttonFrame = CGRect(origin: CGPoint(x: floor((viewport.width - buttonSize.width) * 0.5), y: self.textFrame.maxY + textSpacing), size: buttonSize)
    }
}
