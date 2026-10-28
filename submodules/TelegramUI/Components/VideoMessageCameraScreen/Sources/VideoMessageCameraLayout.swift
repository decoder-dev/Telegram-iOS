import Foundation

struct VideoMessageCameraLayout {
    let previewFrame: CGRect
    let zoomFrame: CGRect

    init(preferredPreviewFrame: CGRect, containerSize: CGSize, topInset: CGFloat) {
        // Keep the entire expanded dial above the bottom camera buttons (40 pt + 8 pt
        // bottom margin), with a separate 8 pt gap. Shrink the circle on short layouts.
        let zoomHeight: CGFloat = 56.0
        let zoomBottom = containerSize.height - 56.0
        let previewBottom = zoomBottom - zoomHeight - 10.0
        let side = min(preferredPreviewFrame.width, max(1.0, previewBottom - topInset))
        let previewY = max(topInset, min(preferredPreviewFrame.minY, previewBottom - side))
        self.previewFrame = CGRect(x: preferredPreviewFrame.midX - side / 2.0, y: previewY, width: side, height: side)

        let zoomWidth = max(1.0, min(240.0, containerSize.width - 72.0))
        self.zoomFrame = CGRect(x: (containerSize.width - zoomWidth) / 2.0, y: self.previewFrame.maxY + 10.0, width: zoomWidth, height: zoomHeight)
    }
}
