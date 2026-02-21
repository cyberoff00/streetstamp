import SwiftUI
import UIKit

/// Read-only selectable text that hides Share and supports selection-copy.
final class CopyOnlyTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)),
             #selector(select(_:)),
             #selector(selectAll(_:)):
            return true
        default:
            return false
        }
    }
}

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let tv = CopyOnlyTextView()
        tv.isEditable = false
        tv.isSelectable = true

        // 关键：必须关掉滚动，让高度由内容决定
        tv.isScrollEnabled = false

        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true

        // 让 SwiftUI 更愿意给它扩展高度
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        para.alignment = .natural

        uiView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]
        )

        // 触发布局更新，配合 sizeThatFits 才能拿到正确高度
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }

    /// ✅ iOS 16+：直接告诉 SwiftUI 这个 UITextView 需要的尺寸
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let target = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fitted = uiView.sizeThatFits(target)
        return CGSize(width: width, height: fitted.height)
    }
}
