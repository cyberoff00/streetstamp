import SwiftUI
import UIKit
import MapKit
import Combine

// =======================================================
// MARK: - Payload (UI 用的数据结构)
// =======================================================

struct UnlockedCityPayload: Identifiable, Equatable {
    let id: String            // cityKey
    let name: String
    let countryISO2: String?
    let baseThumbPath: String?
    let routeThumbPath: String?
}

// =======================================================
// MARK: - ImageLoader (从 Documents 文件路径加载缩略图)
// =======================================================

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage? = nil

    func load(path: String?) {
        guard let path, !path.isEmpty else {
            self.image = nil
            return
        }
        
        // Resolve relative path to full path using the shared thumbnails directory
        guard let fullPath = CityThumbnailCache.resolveFullPath(path) else {
            self.image = nil
            return
        }
        
        let url = URL(fileURLWithPath: fullPath)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            self.image = nil
            return
        }
        self.image = img
    }
}

// =======================================================
// MARK: - Unlock Modal (解锁弹窗)
// =======================================================

struct UnlockCityModal: View {
    let payload: UnlockedCityPayload
    @Binding var isPresented: Bool
    var onGoToLibrary: (() -> Void)? = nil

    @StateObject private var loader = ImageLoader()

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.key("unlock_city_title_cn"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                        Text(payload.name)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    AppCloseButton(style: .filled) {
                        isPresented = false
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // Map thumb
                Group {
                    if let img = loader.image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.00),
                                        Color.black.opacity(0.18)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(UIColor.systemGray6))
                            .frame(height: 220)
                            .overlay(
                                VStack(spacing: 8) {
                                    ProgressView()
                                    Text(L10n.key("loading_map"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(16)

                // Body text
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: L10n.t("unlock_city_desc_1"), payload.name))
                        .font(.system(size: 13))
                        .foregroundColor(.black)

                    Text(L10n.key("unlock_city_desc_2"))
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // Actions
                HStack(spacing: 12) {
                    Button {
                        isPresented = false
                    } label: {
                        Text(L10n.key("got_it"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(height: 42)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(UIColor.systemGray6))
                            )
                    }

                    Button {
                        isPresented = false
                        onGoToLibrary?()
                    } label: {
                        Text(L10n.key("go_see"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(height: 42)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 360)
            .background(Color.white)
            .cornerRadius(16)
            .padding(.horizontal, 18)
            .onAppear {
                // 优先 route 图；没有则 base 图
                loader.load(path: payload.routeThumbPath ?? payload.baseThumbPath)
            }
        }
    }
}
