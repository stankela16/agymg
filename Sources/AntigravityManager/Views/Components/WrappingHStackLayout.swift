import SwiftUI

public struct WrappingHStackLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat

    public init(horizontalSpacing: CGFloat = 6, verticalSpacing: CGFloat = 4) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let constrainedWidth = maxWidth.isFinite ? min(size.width, maxWidth) : size.width

            if currentX > 0 && currentX + constrainedWidth > maxWidth {
                maxLineWidth = max(maxLineWidth, currentX - horizontalSpacing)
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }

            currentX += constrainedWidth + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        if currentX > 0 {
            maxLineWidth = max(maxLineWidth, currentX - horizontalSpacing)
        }
        let totalWidth = maxWidth.isFinite ? min(maxWidth, maxLineWidth) : maxLineWidth
        let totalHeight = subviews.isEmpty ? 0 : (currentY + lineHeight)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var rows: [[(subview: LayoutSubviews.Element, size: CGSize)]] = []
        var currentRow: [(subview: LayoutSubviews.Element, size: CGSize)] = []
        var currentX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let constrainedWidth = min(size.width, maxWidth)

            if currentX > 0 && currentX + constrainedWidth > maxWidth {
                rows.append(currentRow)
                currentRow = []
                currentX = 0
            }

            currentRow.append((subview, CGSize(width: constrainedWidth, height: size.height)))
            currentX += constrainedWidth + horizontalSpacing
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in row {
                let yOffset = (rowHeight - item.size.height) / 2.0
                item.subview.place(
                    at: CGPoint(x: x, y: y + yOffset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }
    }
}
