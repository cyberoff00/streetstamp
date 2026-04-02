import SwiftUI
import UIKit

enum MemoryEditorMediaPolicy {
    static let requiresEditingBeforeSave = true
}

struct PhotoEditingQueueItem {
    let id: String
    let original: UIImage
}

struct PhotoEditingQueueState {
    let items: [PhotoEditingQueueItem]
    private(set) var currentIndex: Int = 0
    private(set) var finalizedItems: [UIImage] = []

    init(items: [PhotoEditingQueueItem], currentIndex: Int = 0, finalizedItems: [UIImage] = []) {
        self.items = items
        self.currentIndex = currentIndex
        self.finalizedItems = finalizedItems
    }

    var isFinished: Bool {
        currentIndex >= items.count
    }

    var currentItem: PhotoEditingQueueItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var primaryActionTitle: String {
        isLastItem ? "Done All" : "Done"
    }

    private var isLastItem: Bool {
        currentIndex == max(0, items.count - 1)
    }

    mutating func completeCurrent(with edited: UIImage) {
        guard currentItem != nil else { return }
        finalizedItems.append(edited)
        currentIndex += 1
    }

    mutating func skipCurrent() {
        guard let item = currentItem else { return }
        finalizedItems.append(item.original)
        currentIndex += 1
    }

    mutating func discardCurrent() {
        guard currentItem != nil else { return }
        currentIndex += 1
    }
}

struct MemoryEditorBootstrapState {
    let title: String
    let notes: String
    let imagePaths: [String]
    let remoteImageURLs: [String]
    let mirrorSelfie: Bool

    static func make(
        draft: MemoryDraft?,
        existing: JourneyMemory?,
        preloadedImagePaths: [String]
    ) -> MemoryEditorBootstrapState {
        if existing == nil, !preloadedImagePaths.isEmpty {
            return MemoryEditorBootstrapState(
                title: "",
                notes: "",
                imagePaths: preloadedImagePaths,
                remoteImageURLs: [],
                mirrorSelfie: false
            )
        }

        if let draft {
            return MemoryEditorBootstrapState(
                title: draft.title,
                notes: draft.notes,
                imagePaths: draft.imagePaths,
                remoteImageURLs: existing?.remoteImageURLs ?? [],
                mirrorSelfie: draft.mirrorSelfie
            )
        }

        return MemoryEditorBootstrapState(
            title: existing?.title ?? "",
            notes: existing?.notes ?? "",
            imagePaths: existing?.imagePaths ?? preloadedImagePaths,
            remoteImageURLs: existing?.remoteImageURLs ?? [],
            mirrorSelfie: false
        )
    }
}

struct PhotoConfirmationView: View {
    let images: [UIImage]
    let onEdit: ([UIImage]) -> Void
    let onUse: ([UIImage]) -> Void
    let onCancel: () -> Void

    @State private var currentIndex = 0

    private var useTitle: String {
        images.count > 1 ? "Use Photos" : "Use Photo"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Spacer(minLength: 12)

                if !images.isEmpty {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                                .padding(.horizontal, 10)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
                }

                Spacer(minLength: 12)

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
            }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Text(L10n.t("cancel"))
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }

            Spacer()

            if images.count > 1 {
                Text("\(currentIndex + 1)/\(images.count)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Button {
                onUse(images)
            } label: {
                Text(useTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                onEdit(images)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Edit")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}
