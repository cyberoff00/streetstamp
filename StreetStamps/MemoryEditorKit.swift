//
//  MemoryEditorKit.swift
//  StreetStamps
//
//  Created by Claire Yang on 31/01/2026.
//  Shared building blocks for Journey Memory editors (Map / CityDeepView / Journey Memory Detail)
//

import SwiftUI
import UIKit

enum MemoryTypography {
    static let font: UIFont = .systemFont(ofSize: 14)
    static let fontSwiftUI: Font = .system(size: 14)
    static let lineSpacing: CGFloat = 8.75
    static let textColor: UIColor = UIColor(red: 0.21, green: 0.26, blue: 0.32, alpha: 1.0)
    static let textColorSwiftUI: Color = Color(red: 0.21, green: 0.26, blue: 0.32)
}

// MARK: - UIKit backed editor to guarantee consistent line spacing across the app.
struct MemoryNotesTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    var isScrollEnabled: Bool = true
    var textContainerInset: UIEdgeInsets = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = isScrollEnabled
        tv.textContainerInset = textContainerInset
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator

        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .no
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .no

        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyStyle(to: tv)
        tv.attributedText = styledAttributed(text)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let selected = uiView.selectedRange
            uiView.attributedText = styledAttributed(text)
            uiView.selectedRange = selected
            applyStyle(to: uiView)
        }

        if isFocused {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
            // ✅ Ensure caret is visible when focusing.
            DispatchQueue.main.async {
                uiView.scrollRangeToVisible(uiView.selectedRange)
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MemoryNotesTextView
        init(_ parent: MemoryNotesTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            // keep typing attributes stable
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = MemoryTypography.lineSpacing
            textView.typingAttributes = [
                .font: MemoryTypography.font,
                .foregroundColor: MemoryTypography.textColor,
                .paragraphStyle: paragraph
            ]
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // ✅ When user taps a position, keep caret visible.
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }
    }

    private func applyStyle(to textView: UITextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = MemoryTypography.lineSpacing
        paragraph.alignment = .natural

        textView.typingAttributes = [
            .font: MemoryTypography.font,
            .foregroundColor: MemoryTypography.textColor,
            .paragraphStyle: paragraph
        ]
    }

    private func styledAttributed(_ string: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = MemoryTypography.lineSpacing
        paragraph.alignment = .natural

        return NSAttributedString(
            string: string,
            attributes: [
                .font: MemoryTypography.font,
                .foregroundColor: MemoryTypography.textColor,
                .paragraphStyle: paragraph
            ]
        )
    }
}

// MARK: - SwiftUI wrapper with placeholder
struct MemoryNotesEditor: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            MemoryNotesTextView(text: $text, isFocused: $isFocused)

            if !placeholder.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocused {
                Text(placeholder)
                    .font(MemoryTypography.fontSwiftUI)
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Keyboard helper
@inline(__always)
func endEditingGlobal() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil,
                                    from: nil,
                                    for: nil)
}


// MARK: - Draft persistence (Journey Memory Editor)

struct MemoryDraft: Codable, Equatable {
    var title: String
    var notes: String
    var imagePaths: [String]
    var mirrorSelfie: Bool
}

enum MemoryDraftStore {
    private static func key(userID: String, memoryID: String) -> String {
        "memory.draft.v1.\(userID).\(memoryID)"
    }

    static func load(userID: String, memoryID: String) -> MemoryDraft? {
        let k = key(userID: userID, memoryID: memoryID)
        guard
            let data = UserDefaults.standard.data(forKey: k),
            let decoded = try? JSONDecoder().decode(MemoryDraft.self, from: data)
        else { return nil }
        return decoded
    }

    static func save(_ draft: MemoryDraft, userID: String, memoryID: String) {
        let k = key(userID: userID, memoryID: memoryID)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: k)
    }

    static func clear(userID: String, memoryID: String) {
        UserDefaults.standard.removeObject(forKey: key(userID: userID, memoryID: memoryID))
    }
}

// MARK: - Draft resume flag
/// Controls whether we should automatically resume the editor the next time the user
/// enters the Memory detail page.
enum MemoryDraftResumeStore {
    private static func key(userID: String, memoryID: String) -> String {
        "memory.draft.resume.v1.\(userID).\(memoryID)"
    }

    static func shouldResume(userID: String, memoryID: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(userID: userID, memoryID: memoryID))
    }

    static func set(_ value: Bool, userID: String, memoryID: String) {
        UserDefaults.standard.set(value, forKey: key(userID: userID, memoryID: memoryID))
    }
}
