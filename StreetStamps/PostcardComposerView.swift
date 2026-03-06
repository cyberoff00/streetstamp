import SwiftUI
import PhotosUI

struct PostcardComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var journeyStore: JourneyStore

    let friendID: String
    let friendName: String
    let onSent: (() -> Void)? = nil

    @State private var selectedCityID: String = ""
    @State private var selectedCityName: String = ""
    @State private var messageText: String = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var localImagePath: String = ""
    @State private var showPreview = false
    @State private var loadingPhoto = false

    private var cityOptions: [(id: String, name: String)] {
        var ordered: [(String, String)] = []

        if let current = currentCityCandidate, !current.id.isEmpty {
            ordered.append(current)
        }

        for city in cityCache.cachedCities {
            let id = city.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = city.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty else { continue }
            if !ordered.contains(where: { $0.0 == id }) {
                ordered.append((id, name))
            }
        }

        return ordered
    }

    private var currentCityCandidate: (id: String, name: String)? {
        if let ongoing = journeyStore.latestOngoing {
            let id = ongoing.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = ongoing.displayCityName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, !name.isEmpty {
                return (id, name)
            }
        }
        if let first = journeyStore.journeys.first {
            let id = first.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = first.displayCityName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, !name.isEmpty {
                return (id, name)
            }
        }
        return nil
    }

    private var canPreview: Bool {
        !selectedCityID.isEmpty && !localImagePath.isEmpty && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("postcard_send_to"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                    Text(friendName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .postcardFeatureCardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("postcard_city"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)

                    Picker(L10n.t("postcard_city"), selection: $selectedCityID) {
                        ForEach(cityOptions, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedCityID) { _, newID in
                        selectedCityName = cityOptions.first(where: { $0.id == newID })?.name ?? ""
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .postcardFeatureCardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("postcard_photo_limit"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)

                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Text(selectedImage == nil ? L10n.t("postcard_upload_local_photo") : L10n.t("postcard_replace_photo"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FigmaTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(loadingPhoto)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .postcardFeatureCardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("postcard_message"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)

                    TextEditor(text: $messageText)
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: messageText) { _, newValue in
                            if newValue.count > 80 {
                                messageText = String(newValue.prefix(80))
                            }
                        }

                    HStack {
                        Spacer()
                        Text("\(messageText.count)/80")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .postcardFeatureCardStyle()

                NavigationLink(isActive: $showPreview) {
                    PostcardPreviewView(
                        friendID: friendID,
                        friendName: friendName,
                        selectedCityID: selectedCityID,
                        selectedCityName: selectedCityName,
                        messageText: messageText,
                        localImagePath: localImagePath,
                        selectedImage: selectedImage,
                        allowedCityIDs: cityOptions.map(\.id),
                        onSent: {
                            onSent?()
                            dismiss()
                        }
                    )
                } label: {
                    EmptyView()
                }

                Button {
                    showPreview = true
                } label: {
                    Text(L10n.t("postcard_preview"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canPreview ? FigmaTheme.primary : FigmaTheme.primary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canPreview)
            }
            .padding(20)
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationTitle(L10n.t("postcard_new_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedCityID.isEmpty, let first = cityOptions.first {
                selectedCityID = first.id
                selectedCityName = first.name
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                loadingPhoto = true
                defer { loadingPhoto = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else { return }
                    let filename = "postcard_\(UUID().uuidString).jpg"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    if let jpeg = uiImage.jpegData(compressionQuality: 0.88) {
                        try jpeg.write(to: url, options: .atomic)
                        selectedImage = uiImage
                        localImagePath = url.path
                    }
                } catch {
                    // ignore picker failure, user can retry
                }
            }
        }
    }
}

private extension View {
    func postcardFeatureCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }
}
