import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arrangement = arrange(maxWidth: maxWidth, subviews: subviews)
        return arrangement.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(maxWidth: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() where index < arrangement.origins.count {
            let origin = arrangement.origins[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(arrangement.sizes[index])
            )
        }
    }

    private func arrange(
        maxWidth: CGFloat,
        subviews: Subviews
    ) -> (size: CGSize, origins: [CGPoint], sizes: [CGSize]) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + lineSpacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: currentX, y: currentY))
            sizes.append(size)

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            usedWidth = max(usedWidth, currentX - spacing)
        }

        let totalHeight = currentY + rowHeight
        let resolvedWidth = maxWidth.isFinite ? maxWidth : usedWidth
        return (CGSize(width: resolvedWidth, height: totalHeight), origins, sizes)
    }
}
