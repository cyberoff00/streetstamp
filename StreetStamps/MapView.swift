//
//  MapView.swift
//  StreetStamps
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit
import Photos
import PhotosUI

// MARK: - Models

struct CoordinateCodable: Codable, Hashable {
    var lat: Double
    var lon: Double
}

extension CoordinateCodable {
    var cl: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

extension Array where Element == CoordinateCodable {
    var clCoords: [CLLocationCoordinate2D] { map(\.cl) }
}

enum JourneyMemoryType: String, Codable {
    case memory
}

enum ExploreMode: String, Codable {
    case city

    // Backward compatibility: decode legacy "interCity" as "city"
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // Map legacy "interCity" to "city"
        self = (rawValue == "interCity") ? .city : (ExploreMode(rawValue: rawValue) ?? .city)
    }
}

struct JourneyMemory: Identifiable, Codable, Equatable {
    var id: String
    var timestamp: Date
    var title: String
    var notes: String
    var imageData: Data? = nil
    var imagePaths: [String] = []

    var cityKey: String? = nil
    var cityName: String? = nil
    var coordinate: (Double, Double)
    var type: JourneyMemoryType

    enum CodingKeys: String, CodingKey {
        case id, timestamp, title, notes, imageData, imagePaths, cityKey, cityName, coordinateLat, coordinateLon, type
    }

    init(
        id: String,
        timestamp: Date,
        title: String,
        notes: String,
        imageData: Data?,
        imagePaths: [String] = [],
        cityKey: String? = nil,
        cityName: String? = nil,
        coordinate: (Double, Double),
        type: JourneyMemoryType
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.notes = notes
        self.imageData = imageData
        self.imagePaths = imagePaths
        self.cityKey = cityKey
        self.cityName = cityName
        self.coordinate = coordinate
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decode(String.self, forKey: .notes)
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        imagePaths = (try? c.decode([String].self, forKey: .imagePaths)) ?? []
        cityKey = try c.decodeIfPresent(String.self, forKey: .cityKey)
        cityName = try c.decodeIfPresent(String.self, forKey: .cityName)
        let lat = try c.decode(Double.self, forKey: .coordinateLat)
        let lon = try c.decode(Double.self, forKey: .coordinateLon)
        coordinate = (lat, lon)
        type = try c.decode(JourneyMemoryType.self, forKey: .type)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(title, forKey: .title)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(imageData, forKey: .imageData)
        if !imagePaths.isEmpty { try c.encode(imagePaths, forKey: .imagePaths) }
        if let cityKey, !cityKey.isEmpty { try c.encode(cityKey, forKey: .cityKey) }
        if let cityName, !cityName.isEmpty { try c.encode(cityName, forKey: .cityName) }
        try c.encode(coordinate.0, forKey: .coordinateLat)
        try c.encode(coordinate.1, forKey: .coordinateLon)
        try c.encode(type, forKey: .type)
    }

    static func == (lhs: JourneyMemory, rhs: JourneyMemory) -> Bool {
        lhs.id == rhs.id &&
        lhs.timestamp == rhs.timestamp &&
        lhs.title == rhs.title &&
        lhs.notes == rhs.notes &&
        lhs.imageData == rhs.imageData &&
        lhs.imagePaths == rhs.imagePaths &&
        lhs.cityKey == rhs.cityKey &&
        lhs.cityName == rhs.cityName &&
        lhs.coordinate.0 == rhs.coordinate.0 &&
        lhs.coordinate.1 == rhs.coordinate.1 &&
        lhs.type == rhs.type
    }
}

// =======================================================
// MARK: - Local Photo Store
// =======================================================

enum PhotoStore {
    static let folderName = "StreetStampsPhotos"

    private static func photosDir(for userID: String) throws -> URL {
        let paths = StoragePath(userID: userID)
        try paths.ensureBaseDirectoriesExist()
        return paths.photosDir
    }

    static func saveJPEG(_ image: UIImage, userID: String, quality: CGFloat = 0.80) throws -> String {
        let dir = try photosDir(for: userID)
        let name = "p_\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(name)

        let thumb = image.downscaled(maxPixel: 1024)
        guard let data = thumb.jpegData(compressionQuality: quality) else {
            throw NSError(
                domain: "PhotoStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("photo_encode_failed")]
            )
        }
        try data.write(to: url, options: .atomic)
        return name
    }

    static func loadImage(named filename: String, userID: String) -> UIImage? {
        let paths = StoragePath(userID: userID)
        let url = paths.photosDir.appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(named filename: String, userID: String) {
        let paths = StoragePath(userID: userID)
        let url = paths.photosDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Image helpers

extension UIImage {
    fileprivate func downscaled(maxPixel: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return self }
        let longest = max(w, h)
        guard longest > maxPixel else { return self }
        let scale = maxPixel / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Mirror horizontally once
    func horizontallyFlipped() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return self }
        ctx.translateBy(x: size.width, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out ?? self
    }
}

// =======================================================
// MARK: - Journey merge helper
// =======================================================
struct JourneyRoute: Codable {
    enum RouteSource: String, Codable {
        case raw
        case corrected
        case matched
    }

    var id: String = UUID().uuidString
    var startTime: Date?
    var endTime: Date?
    var distance: Double = 0
    /// Cumulative paused duration in seconds for this journey.
    var pausedDurationSeconds: TimeInterval = 0
    /// Cumulative moving duration in seconds for this journey.
    var movingDurationSeconds: TimeInterval = 0
    /// Total positive elevation gain (meters).
    var elevationGain: Double = 0
    /// Total negative elevation loss (meters).
    var elevationLoss: Double = 0
    var isTooShort: Bool = false
    var cityKey: String = "Unknown|"
    var canonicalCity: String = "Unknown"
    var coordinates: [CoordinateCodable] = []
    var correctedCoordinates: [CoordinateCodable] = []
    var matchedCoordinates: [CoordinateCodable] = []
    var preferredRouteSource: RouteSource = .raw
    var memories: [JourneyMemory] = []
    var thumbnailCoordinates: [CoordinateCodable] = []
    var countryISO2: String? = nil

    var currentCity: String = "Unknown"
    var cityName: String? = nil
    var startCityKey: String?
    var endCityKey: String?

    var exploreMode: ExploreMode = .city
    var trackingMode: TrackingMode = .daily
    var visibility: JourneyVisibility = .private
    var customTitle: String? = nil
    var activityTag: String? = nil
    var overallMemory: String? = nil

    // ✅ 加回普通 init，修复 “Missing argument for 'from'”
    init(
        id: String = UUID().uuidString,
        startTime: Date? = nil,
        endTime: Date? = nil,
        distance: Double = 0,
        pausedDurationSeconds: TimeInterval = 0,
        movingDurationSeconds: TimeInterval = 0,
        elevationGain: Double = 0,
        elevationLoss: Double = 0,
        isTooShort: Bool = false,
        cityKey: String = "Unknown|",
        canonicalCity: String = "Unknown",
        coordinates: [CoordinateCodable] = [],
        correctedCoordinates: [CoordinateCodable] = [],
        matchedCoordinates: [CoordinateCodable] = [],
        preferredRouteSource: RouteSource = .raw,
        memories: [JourneyMemory] = [],
        thumbnailCoordinates: [CoordinateCodable] = [],
        countryISO2: String? = nil,
        currentCity: String = "Unknown",
        cityName: String? = nil,
        startCityKey: String? = nil,
        endCityKey: String? = nil,
        exploreMode: ExploreMode = .city,
        trackingMode: TrackingMode = .daily,
        visibility: JourneyVisibility = .private,
        customTitle: String? = nil,
        activityTag: String? = nil,
        overallMemory: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.distance = distance
        self.pausedDurationSeconds = pausedDurationSeconds
        self.movingDurationSeconds = movingDurationSeconds
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.isTooShort = isTooShort
        self.cityKey = cityKey
        self.canonicalCity = canonicalCity
        self.coordinates = coordinates
        self.correctedCoordinates = correctedCoordinates
        self.matchedCoordinates = matchedCoordinates
        self.preferredRouteSource = preferredRouteSource
        self.memories = memories
        self.thumbnailCoordinates = thumbnailCoordinates
        self.countryISO2 = countryISO2
        self.currentCity = currentCity
        self.cityName = cityName
        self.startCityKey = startCityKey
        self.endCityKey = endCityKey
        self.exploreMode = exploreMode
        self.trackingMode = trackingMode
        self.visibility = visibility
        self.customTitle = customTitle
        self.activityTag = activityTag
        self.overallMemory = overallMemory
    }

    var isCompleted: Bool { endTime != nil && startTime != nil }

    var displayCityName: String {
        let unknownLocalized = L10n.t("unknown")
        let unknownEN = "Unknown"
        let label = (cityName ?? canonicalCity).trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty,
           label.caseInsensitiveCompare(unknownEN) != .orderedSame,
           label != unknownLocalized {
            return label
        }
        let old = currentCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if old.isEmpty || old.caseInsensitiveCompare(unknownEN) == .orderedSame || old == unknownLocalized {
            return unknownLocalized
        }
        return old
    }

    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, distance
        case pausedDurationSeconds, movingDurationSeconds
        case elevationGain, elevationLoss
        case isTooShort
        case cityKey, canonicalCity
        case coordinates, correctedCoordinates, matchedCoordinates, preferredRouteSource
        case memories, thumbnailCoordinates
        case countryISO2
        case currentCity, cityName, startCityKey, endCityKey
        case exploreMode, trackingMode
        case visibility, customTitle, activityTag, overallMemory

        // 兼容更老字段名（如果你确实历史里用过）
        case coords
    }

    // ✅ 兼容旧数据：缺字段不会解码失败
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        startTime = try c.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)

        distance = try c.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        pausedDurationSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedDurationSeconds) ?? 0
        movingDurationSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .movingDurationSeconds) ?? 0
        elevationGain = try c.decodeIfPresent(Double.self, forKey: .elevationGain) ?? 0
        elevationLoss = try c.decodeIfPresent(Double.self, forKey: .elevationLoss) ?? 0

        isTooShort = try c.decodeIfPresent(Bool.self, forKey: .isTooShort) ?? false

        cityKey = try c.decodeIfPresent(String.self, forKey: .cityKey) ?? "Unknown|"
        canonicalCity = try c.decodeIfPresent(String.self, forKey: .canonicalCity) ?? "Unknown"

        coordinates = try c.decodeIfPresent([CoordinateCodable].self, forKey: .coordinates) ?? []
        // ✅ 可选：兼容老 key coords
        if coordinates.isEmpty {
            coordinates = try c.decodeIfPresent([CoordinateCodable].self, forKey: .coords) ?? []
        }
        correctedCoordinates = try c.decodeIfPresent([CoordinateCodable].self, forKey: .correctedCoordinates) ?? []
        matchedCoordinates = try c.decodeIfPresent([CoordinateCodable].self, forKey: .matchedCoordinates) ?? []
        preferredRouteSource = try c.decodeIfPresent(RouteSource.self, forKey: .preferredRouteSource) ?? .raw

        memories = try c.decodeIfPresent([JourneyMemory].self, forKey: .memories) ?? []
        thumbnailCoordinates = try c.decodeIfPresent([CoordinateCodable].self, forKey: .thumbnailCoordinates) ?? []

        countryISO2 = try c.decodeIfPresent(String.self, forKey: .countryISO2)

        currentCity = try c.decodeIfPresent(String.self, forKey: .currentCity) ?? "Unknown"
        cityName = try c.decodeIfPresent(String.self, forKey: .cityName)
        startCityKey = try c.decodeIfPresent(String.self, forKey: .startCityKey)
        endCityKey = try c.decodeIfPresent(String.self, forKey: .endCityKey)

        exploreMode = try c.decodeIfPresent(ExploreMode.self, forKey: .exploreMode) ?? .city
        trackingMode = try c.decodeIfPresent(TrackingMode.self, forKey: .trackingMode) ?? .daily
        visibility = try c.decodeIfPresent(JourneyVisibility.self, forKey: .visibility) ?? .private
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        activityTag = try c.decodeIfPresent(String.self, forKey: .activityTag)
        overallMemory = try c.decodeIfPresent(String.self, forKey: .overallMemory)
    }

    // ✅ 自己实现 encode，修复 Encodable 合成失败（并且你可以选择写出 coords 兼容）
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)

        try c.encode(distance, forKey: .distance)
        try c.encode(pausedDurationSeconds, forKey: .pausedDurationSeconds)
        try c.encode(movingDurationSeconds, forKey: .movingDurationSeconds)
        try c.encode(elevationGain, forKey: .elevationGain)
        try c.encode(elevationLoss, forKey: .elevationLoss)

        try c.encode(isTooShort, forKey: .isTooShort)

        try c.encode(cityKey, forKey: .cityKey)
        try c.encode(canonicalCity, forKey: .canonicalCity)

        try c.encode(coordinates, forKey: .coordinates)
        if !correctedCoordinates.isEmpty {
            try c.encode(correctedCoordinates, forKey: .correctedCoordinates)
        }
        if !matchedCoordinates.isEmpty {
            try c.encode(matchedCoordinates, forKey: .matchedCoordinates)
        }
        try c.encode(preferredRouteSource, forKey: .preferredRouteSource)
        // 可选：如果你想写出老 key 方便旧版本读取
        // try c.encode(coordinates, forKey: .coords)

        try c.encode(memories, forKey: .memories)
        try c.encode(thumbnailCoordinates, forKey: .thumbnailCoordinates)

        try c.encodeIfPresent(countryISO2, forKey: .countryISO2)

        try c.encode(currentCity, forKey: .currentCity)
        try c.encodeIfPresent(cityName, forKey: .cityName)
        try c.encodeIfPresent(startCityKey, forKey: .startCityKey)
        try c.encodeIfPresent(endCityKey, forKey: .endCityKey)

        try c.encode(exploreMode, forKey: .exploreMode)
        try c.encode(trackingMode, forKey: .trackingMode)
        try c.encode(visibility, forKey: .visibility)
        try c.encodeIfPresent(customTitle, forKey: .customTitle)
        try c.encodeIfPresent(activityTag, forKey: .activityTag)
        try c.encodeIfPresent(overallMemory, forKey: .overallMemory)
    }
}


//
extension JourneyRoute {
    func merged(with other: JourneyRoute) -> JourneyRoute {
        guard self.id == other.id else { return other }

        var out = other

        if self.coordinates.count > other.coordinates.count { out.coordinates = self.coordinates }
        if self.correctedCoordinates.count > other.correctedCoordinates.count { out.correctedCoordinates = self.correctedCoordinates }
        if self.matchedCoordinates.count > other.matchedCoordinates.count { out.matchedCoordinates = self.matchedCoordinates }
        if out.preferredRouteSource == .raw {
            out.preferredRouteSource = self.preferredRouteSource
        }
        if self.thumbnailCoordinates.count > other.thumbnailCoordinates.count { out.thumbnailCoordinates = self.thumbnailCoordinates }
        out.pausedDurationSeconds = max(self.pausedDurationSeconds, other.pausedDurationSeconds)
        out.movingDurationSeconds = max(self.movingDurationSeconds, other.movingDurationSeconds)

        var byId: [String: JourneyMemory] = [:]
        for m in self.memories { byId[m.id] = m }
        for m in other.memories {
            if let old = byId[m.id] { byId[m.id] = (m.timestamp >= old.timestamp) ? m : old }
            else { byId[m.id] = m }
        }
        out.memories = Array(byId.values).sorted(by: { $0.timestamp > $1.timestamp })
        out.visibility = other.visibility
        if let t = other.customTitle, !t.isEmpty { out.customTitle = t }
        if let tag = other.activityTag, !tag.isEmpty { out.activityTag = tag }
        if let memo = other.overallMemory, !memo.isEmpty { out.overallMemory = memo }
        return out
    }

    var displayRouteCoordinates: [CoordinateCodable] {
        switch preferredRouteSource {
        case .matched:
            if !matchedCoordinates.isEmpty { return matchedCoordinates }
            if !correctedCoordinates.isEmpty { return correctedCoordinates }
            return coordinates
        case .corrected:
            if !correctedCoordinates.isEmpty { return correctedCoordinates }
            return coordinates
        case .raw:
            if !coordinates.isEmpty { return coordinates }
            if !correctedCoordinates.isEmpty { return correctedCoordinates }
            return matchedCoordinates
        }
    }
}

enum TravelMode: String, Codable {
    case walk, run, transit, drive, bike, motorcycle, flight, unknown
}

// =======================================================
// MARK: - System Camera (UIImagePickerController)
// =======================================================

struct SystemCameraPicker: UIViewControllerRepresentable {
    var preferredDevice: UIImagePickerController.CameraDevice = .rear
    var mirrorOnCapture: Bool
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator

        if UIImagePickerController.isCameraDeviceAvailable(preferredDevice) {
            picker.cameraDevice = preferredDevice
        }
        if UIImagePickerController.isFlashAvailable(for: picker.cameraDevice) {
            picker.cameraFlashMode = .off
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: SystemCameraPicker
        init(parent: SystemCameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.parent.onCancel()
            }
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = info[.originalImage] as? UIImage
            guard let image = img else {
                picker.dismiss(animated: true) { self.parent.onCancel() }
                return
            }

            let out = self.parent.mirrorOnCapture ? image.horizontallyFlipped() : image

            // ✅ 关键：dismiss 完成后再回调 SwiftUI（避免卡在 Use Photo 页）
            picker.dismiss(animated: true) {
                self.parent.onImage(out)
            }
        }
    }
}

// =======================================================
// MARK: - Photo Library Picker (PHPicker, 支持多选)
// =======================================================

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    var onImages: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit // 0 = 无限制
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) {
                if results.isEmpty {
                    self.parent.onCancel()
                    return
                }

                self.loadImages(from: results)
            }
        }

        private func loadImages(from results: [PHPickerResult]) {
            let group = DispatchGroup()
            var images: [(Int, UIImage)] = [] // (index, image) 保持顺序

            for (index, result) in results.enumerated() {
                group.enter()
                let provider = result.itemProvider

                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { obj, error in
                        defer { group.leave() }
                        if let image = obj as? UIImage {
                            DispatchQueue.main.async {
                                images.append((index, image))
                            }
                        }
                    }
                } else {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                // 按原始顺序排序
                let sorted = images.sorted { $0.0 < $1.0 }.map { $0.1 }
                self.parent.onImages(sorted)
            }
        }
    }
}

// =======================
// MARK: - MapView
// =======================

struct MapView: View {
    @ObservedObject private var tracking = TrackingService.shared

    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @AppStorage(AppSettings.avatarHeadlightEnabledKey) private var avatarHeadlightEnabled = true

    @StateObject private var mapController = JourneyMapController()
    @State private var cameraDistance: CLLocationDistance = 900

    @State private var showMemoryEditor = false
    @State private var showFinishConfirm = false
    @State private var showExitWarning = false
    @State private var exitToastMessage: String = ""
    @State private var now: Date = Date()

    let cityName: String
    @Binding var isPresented: Bool
    @Binding var hasOngoingJourney: Bool
    @Binding var selectedTab: Int
    @Binding var journeyRoute: JourneyRoute

    @Binding var showSharingCard: Bool
    @Binding var sharingJourney: JourneyRoute?

    init(
        cityName: String,
        isPresented: Binding<Bool>,
        hasOngoingJourney: Binding<Bool>,
        selectedTab: Binding<Int>,
        journeyRoute: Binding<JourneyRoute>,
        showSharingCard: Binding<Bool>,
        sharingJourney: Binding<JourneyRoute?>
    ) {
        self.cityName = cityName
        self._isPresented = isPresented
        self._hasOngoingJourney = hasOngoingJourney
        self._selectedTab = selectedTab
        self._journeyRoute = journeyRoute
        self._showSharingCard = showSharingCard
        self._sharingJourney = sharingJourney
    }

    @State private var isUserInteractingWithMap = false
    @State private var followUser = false
    @State private var isResolvingStartCity = false
    @State private var isProcessingHistoricalRoute = false

    @State private var editingMemory: JourneyMemory? = nil

    private func mapCoord(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        tracking.mapReady(c)
    }

    private func mapUserCoord() -> CLLocationCoordinate2D? {
        guard let loc = tracking.userLocation else { return nil }
        return mapCoord(loc.coordinate)
    }

    private var displaySegments: [RenderRouteSegment] { tracking.renderUnifiedSegmentsForMap }
    private var liveTail: [CLLocationCoordinate2D] { tracking.renderLiveTailForMap }
    private func lineWidths(for distance: CLLocationDistance, mode: TravelMode) -> (glow: CGFloat, core: CGFloat) {
        let t = max(0.9, min(2.4, distance / 700.0))
        var core = 6 * t
        var glow = 16 * t

        switch mode {
        case .walk, .run: core *= 1.10; glow *= 1.10
        case .transit: core *= 0.82; glow *= 0.90
        case .bike: core *= 1.05; glow *= 1.10
        case .motorcycle: core *= 1.10; glow *= 1.15
        case .drive: core *= 1.18; glow *= 1.25
        case .flight: core *= 1.05; glow *= 1.05
        case .unknown: core *= 1.00; glow *= 1.00
        }
        return (glow: glow, core: core)
    }

    private enum PersistReason { case coordsTick, memoryAdded, exitToHome, finish, sharingContinue, sharingComplete }

    private func persistSnapshot(_ reason: PersistReason) {
        guard journeyRoute.endTime == nil else {
            journeyStore.flushPersist()
            return
        }
        journeyStore.upsertSnapshotThrottled(journeyRoute, coordCount: tracking.coords.count)
    }

    private func flushSnapshot(_ reason: PersistReason) {
        journeyStore.upsertSnapshotThrottled(journeyRoute, coordCount: tracking.coords.count)
        journeyStore.flushPersist()
    }

    var body: some View {
        ZStack {
            mapLayer
            overlayControls
        }
        .overlay(alignment: .trailing) {
            rightMiddleButtons
        }

        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .top) { exitToast }
        .overlay {
            if showMemoryEditor {
                MemoryEditorSheet(
                    isPresented: $showMemoryEditor,
                    userID: sessionStore.currentUserID,
                    existing: editingMemory,
                    onSave: { draft in
                        if draft == nil {
                            if let existingID = editingMemory?.id,
                               let idx = journeyRoute.memories.firstIndex(where: { $0.id == existingID }) {
                                let removed = journeyRoute.memories.remove(at: idx)
                                for path in removed.imagePaths {
                                    PhotoStore.delete(named: path, userID: sessionStore.currentUserID)
                                }
                                if journeyRoute.endTime == nil { persistSnapshot(.memoryAdded) }
                            }
                            editingMemory = nil
                            return
                        }
                        guard var m = draft else { return }
                        if let existingID = editingMemory?.id,
                           let idx = journeyRoute.memories.firstIndex(where: { $0.id == existingID }) {
                            m.id = existingID
                            m.timestamp = journeyRoute.memories[idx].timestamp
                            m.coordinate = journeyRoute.memories[idx].coordinate
                            m.type = .memory
                            journeyRoute.memories[idx] = m
                            if journeyRoute.endTime == nil { persistSnapshot(.memoryAdded) }
                            editingMemory = m
                            onboardingGuide.advance(.recordMemory)
                        } else {
                            guard let loc = tracking.userLocation else { return }
                            m.id = UUID().uuidString
                            m.timestamp = Date()
                            m.coordinate = (loc.coordinate.latitude, loc.coordinate.longitude)
                            m.type = .memory
                            let mid = m.id
                            journeyRoute.memories.append(m)
                            if journeyRoute.endTime == nil { persistSnapshot(.memoryAdded) }
                            assignCityToMemory(memoryID: mid, coordinate: loc.coordinate)
                            onboardingGuide.advance(.recordMemory)
                        }
                    }
                )
            }
        }
        .onChange(of: showMemoryEditor) { visible in
            if !visible { editingMemory = nil }
        }
        .alert(L10n.t("finish_confirm_title"), isPresented: $showFinishConfirm) {
            Button(L10n.t("finish_confirm_finish"), role: .destructive) { finishJourney() }
            Button(L10n.t("finish_confirm_continue"), role: .cancel) {}
        } message: {
            Text(L10n.t("finish_confirm_message"))
        }
        .onAppear {
            onAppearSetup()
            groupedMemoriesCache = computeGroupedMemories()
        }
        .onChange(of: journeyRoute.memories) { _ in
            groupedMemoriesCache = computeGroupedMemories()
        }
        .onDisappear {
            tracking.deactivateMapRenderingSurface()
            if journeyRoute.endTime == nil { flushSnapshot(.exitToHome) }
        }
        .onReceive(tracking.$coords) { onCoordsUpdated($0) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) {
            now = $0
            tracking.refreshDurations(now: $0)
            syncTimingFields()
        }
        .onReceive(tracking.$userLocation.compactMap { $0 }) { loc in
            if followUser, !isUserInteractingWithMap {
                updateCamera(for: loc)
            }
            if shouldResolveStartCity() {
                reverseGeocodeAndSetRouteCity(loc.coordinate)
            }
        }
        // ✅ 监听从锁屏 Widget 触发的"添加记忆"操作
        .onReceive(NotificationCenter.default.publisher(for: .openAddMemoryFromWidget)) { _ in
            guard tracking.isTracking && !tracking.isPaused else { return }
            editingMemory = nil
            showMemoryEditor = true
        }
        // ✅ 监听从锁屏 Widget 触发的"暂停/继续"操作
        .onReceive(NotificationCenter.default.publisher(for: .togglePauseFromWidget)) { _ in
            guard tracking.isTracking else { return }
            if tracking.isPaused {
                tracking.resumeFromPause()
            } else {
                tracking.pauseJourney()
            }
        }
    }

    // =======================
    // MARK: - Map Layer
    // =======================
    private var rightMiddleButtons: some View {
        VStack(spacing: 14) {
            floatingActionButton(icon: "scope", label: "LOCATE", dark: false) {
                followUser = false
                if let loc = tracking.userLocation { updateCamera(for: loc) }
            }

            floatingActionButton(icon: "camera", label: "CAPTURE", dark: true) {
                editingMemory = nil
                showMemoryEditor = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 24)
    }

    private var mapLayer: some View {
        JourneyMKMapView(
            controller: mapController,
            userCoordinate: mapUserCoord(),
            headingDegrees: tracking.headingDegrees,
            headlightEnabled: avatarHeadlightEnabled,
            travelMode: tracking.mode,
            segments: displaySegments,
            liveTail: liveTail,
            memoryGroups: groupedMemoriesCache,
            cameraDistance: $cameraDistance,
            followUser: $followUser,
            isUserInteracting: $isUserInteractingWithMap
        ) { items in
            let sorted = items.sorted { $0.timestamp > $1.timestamp }
            guard let first = sorted.first else { return }
            editingMemory = first
            showMemoryEditor = true
        }
        .ignoresSafeArea()
    }

    // =======================
    // MARK: - Overlay Controls
    // =======================

    private var overlayControls: some View {
        ZStack {
            VStack {
                topTrackingHeader
                Spacer()
            }

            VStack {
                HStack {
                    distanceTimeChip
                    Spacer()
                    gpsStatusChip
                }
                .padding(.horizontal, 32)
                .padding(.top, 100)
                Spacer()
            }

            VStack {
                Spacer()
                bottomTrackingButtons
            }
        }
    }

    private var topTrackingHeader: some View {
        ZStack {
            Text(journeyRoute.displayCityName.uppercased())
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.9)
                .foregroundColor(FigmaTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 64)

            HStack {
                Button {
                    if tracking.isPaused {
                        exitToastMessage = L10n.t("journey_paused")
                        showExitWarning = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showExitWarning = false
                            exitToHomePaused()
                        }
                    } else {
                        exitToastMessage = L10n.t("continue_background")
                        showExitWarning = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showExitWarning = false
                            exitToHomeLowPower()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(FigmaTheme.text)
                        .frame(width: 32, alignment: .leading)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var distanceTimeChip: some View {
        Text("\(distanceText) · \(elapsedText)")
            .font(.system(size: 14, weight: .semibold))
            .tracking(-0.5)
            .foregroundColor(FigmaTheme.text)
            .padding(.horizontal, 20)
            .frame(height: 36)
            .background(Color.white.opacity(0.78))
            .clipShape(Capsule(style: .continuous))
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 2)
    }

    private var gpsStatusChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(gpsStatusColor)
            Text(gpsStatusLabel)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(FigmaTheme.text.opacity(0.72))
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(height: 32)
        .background(Color.white.opacity(0.72))
        .overlay(
            Capsule(style: .continuous)
                .stroke(gpsStatusColor.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    private var bottomTrackingButtons: some View {
        HStack(spacing: 16) {
            Button {
                if tracking.isPaused { tracking.resumeFromPause() }
                else { tracking.pauseJourney() }
            } label: {
                Text(tracking.isPaused ? "RESUME" : "PAUSE")
                    .font(.system(size: 34 / 2, weight: .bold))
                    .tracking(-0.85)
                    .foregroundColor(FigmaTheme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.white.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            Button { showFinishConfirm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                    Text(L10n.t("finish_upper"))
                        .font(.system(size: 34 / 2, weight: .bold))
                        .tracking(-0.85)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var elapsedText: String {
        let seconds = max(0, Int(currentMovingDuration()))
        return formatDuration(seconds)
    }

    private var distanceText: String {
        let d = max(0, tracking.totalDistance)
        if d < 1000 { return String(format: "%.0f m", d) }
        return String(format: "%.2f km", d / 1000)
    }

    private var gpsStatusLabel: String {
        guard let acc = tracking.userLocation?.horizontalAccuracy else { return "GPS --" }
        if acc <= 20 { return "GPS GOOD" }
        if acc <= 50 { return "GPS FAIR" }
        return "GPS WEAK"
    }

    private var gpsStatusColor: Color {
        guard let acc = tracking.userLocation?.horizontalAccuracy else { return Color.gray }
        if acc <= 20 { return FigmaTheme.primary }
        if acc <= 50 { return FigmaTheme.secondary }
        return Color.gray
    }

    private func floatingActionButton(icon: String, label: String, dark: Bool, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(dark ? .white : .black)
                    .frame(width: 64, height: 64)
                    .background(dark ? Color.black : Color.white.opacity(0.95))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 4)
                    .overlay {
                        if highlighted {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        }
                    }
                    .scaleEffect(highlighted ? 1.06 : 1.0)

                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.62)
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
    }

    private var exitToast: some View {
        Group {
            if showExitWarning {
                VStack {
                    Text(exitToastMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.85))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // =======================
    // MARK: - Lifecycle / Updates
    // =======================

    private func onAppearSetup() {
        if journeyRoute.endTime == nil {
            journeyRoute.currentCity = cityName
            journeyRoute.cityName = cityName
        }

        tracking.activateMapRenderingSurface()

        if !(tracking.isTracking && journeyRoute.endTime == nil) {
            tracking.syncFromJourneyIfNeeded(journeyRoute)
        }

        if journeyRoute.endTime == nil {
            journeyRoute.startTime = journeyRoute.startTime ?? Date()
            tracking.resumeJourney(
                startTime: journeyRoute.startTime,
                restoredPausedDuration: journeyRoute.pausedDurationSeconds
            )
            hasOngoingJourney = true
        } else {
            hasOngoingJourney = false
            maybeProcessHistoricalRouteLazily()
        }

        tracking.activateMapRenderingSurface()
        tracking.requestRefresh()
        autoFitOnceOnEnter()

        followUser = true
        if let loc = tracking.userLocation { updateCamera(for: loc) }

        // ✅ City key/name should be frozen to the journey START city (Memory 城市 = 起点).
        // Only set it once (when unknown), and prefer the start coordinate if available.
        if shouldResolveStartCity() {
            if let start = journeyRoute.startCoordinate {
                reverseGeocodeAndSetRouteCity(start)
            } else if let loc = tracking.userLocation {
                reverseGeocodeAndSetRouteCity(loc.coordinate)
            }
        }

        // ✅ Ensure the displayed city title follows the *current* device language.
        // Journey snapshots may have been created under a different language; we refresh
        // the display title using the locale-aware cache/key without mutating the cityKey.
        let key = (journeyRoute.startCityKey ?? journeyRoute.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && key != "Unknown|" {
            Task {
                if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key),
                   !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run {
                        journeyRoute.cityName = cached
                        journeyRoute.currentCity = cached
                    }
                    return
                }

                if let start = journeyRoute.startCoordinate, start.isValid {
                    let loc = CLLocation(latitude: start.latitude, longitude: start.longitude)
                    if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key),
                       !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await MainActor.run {
                            journeyRoute.cityName = title
                            journeyRoute.currentCity = title
                        }
                    }
                }
            }
        }
    }

    private func reverseGeocodeAndSetRouteCity(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        // ✅ Freeze to start city: do not override once we have a non-unknown city key.
        if journeyRoute.endTime != nil { return }
        if isResolvingStartCity { return }
        let existingKey = (journeyRoute.startCityKey ?? journeyRoute.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingKey.isEmpty && existingKey != "Unknown|" { return }
        isResolvingStartCity = true

        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Task {
            defer {
                Task { @MainActor in
                    isResolvingStartCity = false
                }
            }
            if let canon = await ReverseGeocodeService.shared.canonical(for: loc) {
                let display = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: canon.cityKey)
                await MainActor.run {
                    // ✅ Record start city key once; keep cityKey aligned to start city.
                    let canonKey = canon.cityKey
                    let existingStart = (journeyRoute.startCityKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if existingStart.isEmpty || existingStart == "Unknown|" {
                        journeyRoute.startCityKey = canonKey
                    }
                    journeyRoute.cityKey = journeyRoute.startCityKey ?? canonKey
                    journeyRoute.canonicalCity = canon.cityName
                    journeyRoute.countryISO2 = canon.iso2 ?? journeyRoute.countryISO2

                    let disp = (display ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !disp.isEmpty {
                        journeyRoute.cityName = disp
                        journeyRoute.currentCity = disp
                    } else {
                        let fallback = (journeyRoute.cityName ?? canon.cityName).trimmingCharacters(in: .whitespacesAndNewlines)
                        journeyRoute.cityName = fallback
                        journeyRoute.currentCity = fallback
                    }
                }
                return
            }

            let cityKey = await MainActor.run { journeyRoute.cityKey }
            if !cityKey.isEmpty,
               let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: cityKey),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    journeyRoute.cityName = cached
                    journeyRoute.currentCity = cached
                }
            }
        }
    }

    private func shouldResolveStartCity() -> Bool {
        guard journeyRoute.endTime == nil else { return false }
        let key = (journeyRoute.startCityKey ?? journeyRoute.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || key == "Unknown|"
    }

    @State private var didAutoFitOnEnter = false
    private func autoFitOnceOnEnter() {
        guard !didAutoFitOnEnter else { return }
        didAutoFitOnEnter = true

        if let user = mapUserCoord() {
            mapController.setRegion(.init(center: user, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            return
        }

        let all = tracking.renderUnifiedSegmentsForMap.flatMap { $0.coords }
        if all.count >= 2 {
            autoFitMap(to: all)
            return
        }

        if let last = tracking.coords.last {
            mapController.setRegion(.init(center: mapCoord(last), span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        }
    }

    private func onCoordsUpdated(_ coords: [CLLocationCoordinate2D]) {
        journeyRoute.coordinates = coords.map { .init(lat: $0.latitude, lon: $0.longitude) }
        journeyRoute.distance = tracking.totalDistance
        journeyRoute.elevationGain = tracking.totalAscent
        journeyRoute.elevationLoss = tracking.totalDescent
        syncTimingFields()
        guard journeyRoute.endTime == nil else { return }
        persistSnapshot(.coordsTick)
    }

    private func updateCamera(for location: CLLocation) {
        followUserCamera(to: location)
    }

    private func followUserCamera(to location: CLLocation) {
        let d: CLLocationDistance
        switch tracking.mode {
        case .walk, .run: d = 650
        case .bike: d = 900
        case .transit: d = 1200
        case .motorcycle: d = 1600
        case .drive: d = 2000
        case .flight: d = 8000
        case .unknown: d = 900
        }

        cameraDistance = d
        let center = mapCoord(location.coordinate)
        mapController.setCamera(center: center, distance: d, heading: 0, pitch: 0)
    }

    private func autoFitMap(to coordinates: [CLLocationCoordinate2D]) {
        guard let last = coordinates.last else {
            if let u = mapUserCoord() {
                mapController.setRegion(.init(center: u, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            }
            return
        }

        guard coordinates.count > 1 else {
            mapController.setRegion(.init(center: last, span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            return
        }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)

        let padding: Double = 1.25
        let minSpan: Double = 0.008
        let maxSpan: Double = 0.22

        let rawLat = (maxLat - minLat) * padding
        let rawLon = (maxLon - minLon) * padding

        let latDelta = min(max(rawLat, minSpan), maxSpan)
        let lonDelta = min(max(rawLon, minSpan), maxSpan)

        mapController.setRegion(.init(center: center, span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta)))
    }

    private func finishJourney() {
        onboardingGuide.advance(.finishJourney)
        syncTimingFields()
        journeyRoute.endTime = Date()
        hasOngoingJourney = false
        tracking.stopJourney()

        autoFitMap(to: tracking.coords.map { mapCoord($0) })

        JourneyFinalizer.finalize(
            route: journeyRoute,
            journeyStore: journeyStore,
            cityCache: cityCache,
            lifelogStore: lifelogStore,
            source: .userConfirmedFinish
        ) { updated in
            journeyRoute = updated
            sharingJourney = updated
            showSharingCard = true
            selectedTab = 0
            isPresented = false
        }
    }

    private func maybeProcessHistoricalRouteLazily() {
        guard journeyRoute.endTime != nil else { return }
        guard !isProcessingHistoricalRoute else { return }
        guard journeyRoute.correctedCoordinates.isEmpty || journeyRoute.matchedCoordinates.isEmpty else { return }

        isProcessingHistoricalRoute = true
        let snapshot = journeyRoute

        Task {
            let processed = await JourneyRoutePostProcessor.processIfNeeded(snapshot)
            await MainActor.run {
                defer { isProcessingHistoricalRoute = false }
                guard processed.id == journeyRoute.id else { return }
                guard processed.correctedCoordinates != journeyRoute.correctedCoordinates ||
                        processed.matchedCoordinates != journeyRoute.matchedCoordinates ||
                        processed.preferredRouteSource != journeyRoute.preferredRouteSource else {
                    return
                }

                journeyRoute = processed
                tracking.syncFromJourneyIfNeeded(processed)
                journeyStore.upsertSnapshotThrottled(processed, coordCount: processed.coordinates.count)
                journeyStore.flushPersist(journey: processed)
            }
        }
    }

    private func currentMovingDuration() -> TimeInterval {
        if journeyRoute.endTime == nil {
            return tracking.movingDuration(at: now)
        }
        if journeyRoute.movingDurationSeconds > 0 {
            return journeyRoute.movingDurationSeconds
        }
        guard let start = journeyRoute.startTime, let end = journeyRoute.endTime else { return 0 }
        let elapsed = max(0, end.timeIntervalSince(start))
        return max(0, elapsed - max(0, journeyRoute.pausedDurationSeconds))
    }

    private func syncTimingFields() {
        journeyRoute.pausedDurationSeconds = tracking.pausedDuration(at: now)
        journeyRoute.movingDurationSeconds = tracking.movingDuration(at: now)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func exitToHomeLowPower() {
        TrackingService.shared.enterLowPowerBackgroundMode()
        if journeyRoute.endTime == nil { flushSnapshot(.exitToHome) }
        hasOngoingJourney = true
        selectedTab = 0
        isPresented = false
    }

    private func exitToHomePaused() {
        if journeyRoute.endTime == nil { flushSnapshot(.exitToHome) }
        hasOngoingJourney = true
        selectedTab = 0
        isPresented = false
    }

    private func assignCityToMemory(memoryID: String, coordinate: CLLocationCoordinate2D) {
        // ✅ Memory 城市 = Journey 起点城市（不做拍摄点 reverse geocode）
        let key = (journeyRoute.startCityKey ?? journeyRoute.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (journeyRoute.cityName ?? journeyRoute.displayCityName).trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.main.async {
            if let idx = journeyRoute.memories.firstIndex(where: { $0.id == memoryID }) {
                journeyRoute.memories[idx].cityKey = key.isEmpty ? "Unknown|" : key
                journeyRoute.memories[idx].cityName = name.isEmpty ? L10n.t("unknown") : name

                if journeyRoute.endTime == nil { persistSnapshot(.memoryAdded) }
                journeyStore.upsertSnapshotThrottled(journeyRoute, coordCount: journeyRoute.coordinates.count)
            }
        }
    }

    @State private var groupedMemoriesCache: [(key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory])] = []

    /// Group memories within ~20m into a single pin (tap -> list).
    /// This matches the product requirement: notes added within 20m are aggregated.
    private func computeGroupedMemories() -> [(key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory])] {
        let thresholdMeters: CLLocationDistance = 20

        // Stable ordering helps keep grouping deterministic.
        let src = journeyRoute.memories.sorted { $0.timestamp < $1.timestamp }

        var clusters: [(key: String, center: CLLocationCoordinate2D, items: [JourneyMemory])] = []

        func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }

        for m in src {
            let coord = CLLocationCoordinate2D(latitude: m.coordinate.0, longitude: m.coordinate.1)
            guard coord.isValid else { continue }

            // Try to attach to an existing cluster within 20m.
            if let idx = clusters.firstIndex(where: { distance($0.center, coord) <= thresholdMeters }) {
                clusters[idx].items.append(m)
            } else {
                // Key is derived from the first item id; deterministic for the same dataset ordering.
                clusters.append((key: "cluster_\(m.id)", center: coord, items: [m]))
            }
        }

        return clusters.map { c in
            (c.key, mapCoord(c.center), c.items)
        }
    }
}

// =======================
// MARK: - Modifiers
// =======================

private struct UserGestureDetection: ViewModifier {
    @Binding var isUserInteracting: Bool
    @Binding var followUser: Bool

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        isUserInteracting = true
                        followUser = false
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            isUserInteracting = false
                        }
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { _ in
                        isUserInteracting = true
                        followUser = false
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            isUserInteracting = false
                        }
                    }
            )
    }
}

// =======================
// MARK: - Pins & cluster
// =======================
struct MemoryClusterView: View {
    let memories: [JourneyMemory]
    @Binding var isPresented: Bool
    let onOpenDetail: (JourneyMemory) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t("memory_spot_title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(memories) { m in
                            Button {
                                isPresented = false
                                onOpenDetail(m)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: m.imagePaths.isEmpty ? "note.text" : "photo")
                                        .foregroundColor(.blue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(m.title.isEmpty ? "Memory" : m.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(FigmaTheme.text)

                                        Text(m.timestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 11))
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 340, maxHeight: 520)
            .background(Color.white)
            .cornerRadius(12)
        }
    }
}

struct MemoryDetailPage: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    let memory: JourneyMemory
    @Binding var isPresented: Bool
    let onUpdated: (JourneyMemory?) -> Void

    @State private var showViewer: Bool = false
    @State private var viewerIndex: Int = 0
    @State private var showEditor: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.key("tab_memory"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)

                    Spacer()

                    HStack(spacing: 10) {
                        Button { showEditor = true } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.gray)
                        }

                        Button { isPresented = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !memory.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(memory.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(FigmaTheme.text)
                        }

                        if !memory.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(memory.notes)
                                .font(.system(size: 14))
                                .foregroundColor(FigmaTheme.text.opacity(0.85))
                        }

                        if !memory.imagePaths.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(memory.imagePaths.enumerated()), id: \.offset) { idx, p in
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(UIColor(white: 0.92, alpha: 1)))
                                                .frame(width: 88, height: 88)

                                            if let img = PhotoStore.loadImage(named: p, userID: sessionStore.currentUserID) {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 88, height: 88)
                                                    .clipped()
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                        }
                                        .onTapGesture {
                                            viewerIndex = idx
                                            showViewer = true
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Divider()

                        Text(memory.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                    .padding(16)
                }
                .frame(maxWidth: 340, maxHeight: 520)
            }
            .background(Color.white)
            .cornerRadius(12)
        }
        .fullScreenCover(isPresented: $showViewer) {
            PhotoViewer(
                imagePaths: memory.imagePaths,
                userID: sessionStore.currentUserID,
                startIndex: viewerIndex,
                onClose: { showViewer = false }
            )
        }
        .overlay {
            if showEditor {
                MemoryEditorSheet(
                    isPresented: $showEditor,
                    userID: sessionStore.currentUserID,
                    existing: memory,
                    onSave: { updated in
                        onUpdated(updated)
                        showEditor = false
                        if updated == nil { isPresented = false }
                    }
                )
            }
        }
        .onAppear {
            // ✅ If user left mid-edit (Back gesture), automatically resume editing.
            let uid = sessionStore.currentUserID
            let mid = memory.id
            if MemoryDraftResumeStore.shouldResume(userID: uid, memoryID: mid),
               MemoryDraftStore.load(userID: uid, memoryID: mid) != nil {
                showEditor = true
            } else {
                // Keep resume flag clean if draft was cleared.
                MemoryDraftResumeStore.set(false, userID: uid, memoryID: mid)
            }
        }
    }
}

// =======================================================
// MARK: - Unified Memory Editor (System Camera, Photo Library, mirror toggle)
// =======================================================

struct MemoryEditorSheet: View {
    @Binding var isPresented: Bool
    let userID: String
    let existing: JourneyMemory?
    let onSave: (JourneyMemory?) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var imagePaths: [String]
    @State private var notesFocused: Bool = false

    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var showPhotoViewer = false
    @State private var viewerIndex = 0
    @State private var showExpanded = false
    @State private var showDiscardAlert = false
    @State private var showDeleteAlert = false

    // ✅ Used to decide whether we should auto-resume the editor when user returns
    // (Back gesture / swipe-dismiss). Save & Cancel will set this to true.
    @State private var didExitExplicitly: Bool = false

    /// ✅ 镜像开关：默认不镜像
    @State private var mirrorSelfie: Bool = false
    @State private var initialTitle: String
    @State private var initialNotes: String
    @State private var initialImagePaths: [String]
    @State private var initialMirrorSelfie: Bool
    private let maxPhotos = 3

    private func hideKeyboard() {
        endEditingGlobal()
    }

    init(
        isPresented: Binding<Bool>,
        userID: String,
        existing: JourneyMemory?,
        onSave: @escaping (JourneyMemory?) -> Void
    ) {
        self._isPresented = isPresented
        self.userID = userID
        self.existing = existing
        self.onSave = onSave

        let memoryID = existing?.id ?? "new"
        if let draft = MemoryDraftStore.load(userID: userID, memoryID: memoryID) {
            _title = State(initialValue: draft.title)
            _notes = State(initialValue: draft.notes)
            _imagePaths = State(initialValue: draft.imagePaths)
            _mirrorSelfie = State(initialValue: draft.mirrorSelfie)
        } else {
            _title = State(initialValue: existing?.title ?? "")
            _notes = State(initialValue: existing?.notes ?? "")
            _imagePaths = State(initialValue: existing?.imagePaths ?? [])
            _mirrorSelfie = State(initialValue: false)
        }

        _initialTitle = State(initialValue: existing?.title ?? "")
        _initialNotes = State(initialValue: existing?.notes ?? "")
        _initialImagePaths = State(initialValue: existing?.imagePaths ?? [])
        _initialMirrorSelfie = State(initialValue: false)
    }

private var draftMemoryID: String { existing?.id ?? "new" }

private func persistDraft() {
    let d = MemoryDraft(title: title, notes: notes, imagePaths: imagePaths, mirrorSelfie: mirrorSelfie)
    MemoryDraftStore.save(d, userID: userID, memoryID: draftMemoryID)
}

private func clearDraft() {
    MemoryDraftStore.clear(userID: userID, memoryID: draftMemoryID)
}

private var hasUnsavedChanges: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != initialTitle.trimmingCharacters(in: .whitespacesAndNewlines) ||
        notes.trimmingCharacters(in: .whitespacesAndNewlines) != initialNotes.trimmingCharacters(in: .whitespacesAndNewlines) ||
        imagePaths != initialImagePaths ||
        mirrorSelfie != initialMirrorSelfie
    }
    private var canAddPhoto: Bool { imagePaths.count < maxPhotos }
    private var remainingPhotoSlots: Int { max(0, maxPhotos - imagePaths.count) }

    private func dismissSmart() {
        if hasUnsavedChanges { showDiscardAlert = true }
        else { closeWithoutSaving() }
    }


    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture {
                    notesFocused = false
                    endEditingGlobal()
                    dismissSmart()
                }

            VStack {
                Spacer().frame(height: 92)

                VStack(spacing: 0) {
                    header
                    content
                    footer
                }
                .frame(maxWidth: 430)
                .background(FigmaTheme.mutedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .shadow(color: Color.black.opacity(0.25), radius: 32, x: 0, y: 12)

                Spacer()
            }
            .padding(.horizontal, 18)
        }
        
.onChange(of: title) { _ in persistDraft() }
.onChange(of: notes) { _ in persistDraft() }
.onChange(of: imagePaths) { _ in persistDraft() }
.onChange(of: mirrorSelfie) { _ in persistDraft() }
.interactiveDismissDisabled(hasUnsavedChanges)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // ✅ If the app is backgrounded / killed, keep the draft
            if !didExitExplicitly, hasUnsavedChanges {
                persistDraft()
                MemoryDraftResumeStore.set(true, userID: userID, memoryID: draftMemoryID)
            }
        }
        .onDisappear {
            // ✅ Back gesture / swipe-dismiss should keep editing state
            // unless user explicitly saved or canceled.
            if !didExitExplicitly, hasUnsavedChanges {
                persistDraft()
                MemoryDraftResumeStore.set(true, userID: userID, memoryID: draftMemoryID)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            SystemCameraPicker(
                preferredDevice: .rear,
                mirrorOnCapture: mirrorSelfie,
                onImage: { image in
                    // 这里回调已经在 UIKit dismiss completion 之后触发
                    showCamera = false
                    appendCaptured(image)
                },
                onCancel: {
                    showCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker(
                selectionLimit: max(1, remainingPhotoSlots),
                onImages: { images in
                    showPhotoLibrary = false
                    appendPhotosFromLibrary(images)
                },
                onCancel: {
                    showPhotoLibrary = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showExpanded) {
            NavigationStack {
                MemoryEditorPage(
                    title: $title,
                    notes: $notes,
                    imagePaths: $imagePaths,
                    userID: userID,
                    mirrorSelfie: $mirrorSelfie,
                    maxPhotos: maxPhotos,
                    isNew: existing == nil,
                    onDelete: existing == nil ? nil : { deleteExistingMemory() },
                    onClose: { showExpanded = false },
                    onSave: { saveAndDismiss() }
                )
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            PhotoViewer(
                imagePaths: imagePaths,
                userID: userID,
                startIndex: viewerIndex,
                onClose: { showPhotoViewer = false }
            )
        }
        .alert("丢弃更改？", isPresented: $showDiscardAlert) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("discard"), role: .destructive) { closeWithoutSaving() }
        } message: {
            Text(L10n.t("discard_edit_message"))
        }
        .alert(L10n.t("delete_memory_confirm_title"), isPresented: $showDeleteAlert) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("delete"), role: .destructive) { deleteExistingMemory() }
        } message: {
            Text(L10n.t("delete_memory_confirm_message"))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(existing == nil ? L10n.key("add_memory") : L10n.key("edit_memory"))
                .appHeaderStyle()
                .foregroundColor(FigmaTheme.text)

            Spacer()

            Button { showExpanded = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button { dismissSmart() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if existing != nil {
                Button { showDeleteAlert = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .background(Color.white)
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                MemoryNotesEditor(text: $notes, isFocused: $notesFocused, placeholder: L10n.t("memory_notes_placeholder"))
                    .frame(minHeight: 188, maxHeight: 240)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)

                if !imagePaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(imagePaths.enumerated()), id: \.offset) { idx, p in
                                ZStack(alignment: .topTrailing) {
                                    PhotoThumb(path: p, userID: userID)
                                        .onTapGesture {
                                            viewerIndex = idx
                                            showPhotoViewer = true
                                        }

                                    Button {
                                        let removed = imagePaths.remove(at: idx)
                                        PhotoStore.delete(named: removed, userID: userID)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(FigmaTheme.text.opacity(0.6))
                                            .background(Color.white.opacity(0.75).clipShape(Circle()))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(minHeight: 290)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .onTapGesture {
                notesFocused = false
                hideKeyboard()
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 12) {
                Button { showCamera = true } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canAddPhoto)
                .opacity(canAddPhoto ? 1 : 0.35)

                Button { showPhotoLibrary = true } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canAddPhoto)
                .opacity(canAddPhoto ? 1 : 0.35)
            }
            Spacer()

            Button { saveAndDismiss() } label: {
                Text(L10n.t("save").uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .frame(height: 48)
                    .background(UITheme.accent)
                    .clipShape(Capsule(style: .continuous))
                    .shadow(color: UITheme.accent.opacity(0.22), radius: 10, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func saveAndDismiss() {
        didExitExplicitly = true
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let draft = JourneyMemory(
            id: existing?.id ?? UUID().uuidString,
            timestamp: existing?.timestamp ?? Date(),
            title: trimmedTitle,
            notes: trimmedNotes,
            imageData: nil,
            imagePaths: imagePaths,
            cityKey: existing?.cityKey,
            cityName: existing?.cityName,
            coordinate: existing?.coordinate ?? (0, 0),
            type: .memory
        )
        onSave(draft)
        clearDraft()
        MemoryDraftResumeStore.set(false, userID: userID, memoryID: draftMemoryID)
        isPresented = false
    }

    private func closeWithoutSaving() {
        didExitExplicitly = true
        clearDraft()
        MemoryDraftResumeStore.set(false, userID: userID, memoryID: draftMemoryID)
        isPresented = false
    }

    private func deleteExistingMemory() {
        guard existing != nil else { return }
        didExitExplicitly = true
        clearDraft()
        MemoryDraftResumeStore.set(false, userID: userID, memoryID: draftMemoryID)
        onSave(nil)
        isPresented = false
    }


    private func appendCaptured(_ image: UIImage) {
        guard canAddPhoto else { return }
        if let filename = try? PhotoStore.saveJPEG(image, userID: userID) {
            imagePaths.append(filename)
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: nil)
        }
    }

    /// 从相册选择的照片（不保存回相册，因为本来就在相册里）
    private func appendPhotosFromLibrary(_ images: [UIImage]) {
        guard canAddPhoto else { return }
        for image in images {
            if !canAddPhoto { break }
            if let filename = try? PhotoStore.saveJPEG(image, userID: userID) {
                imagePaths.append(filename)
            }
        }
    }
}

struct PhotoThumb: View {
    let path: String
    let userID: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(UITheme.iconBtnBg)
                .frame(width: 76, height: 76)

            if let img = PhotoStore.loadImage(named: path, userID: userID) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(UITheme.subText)
            }
        }
    }
}

// =======================================================
// MARK: - Full-screen editor page
// =======================================================

struct MemoryEditorPage: View {
    @Binding var title: String
    @Binding var notes: String
    @Binding var imagePaths: [String]
    let userID: String
    @Binding var mirrorSelfie: Bool
    let maxPhotos: Int
    let isNew: Bool

    let onDelete: (() -> Void)?
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var notesFocused: Bool = false
    @State private var showCamera: Bool = false
    @State private var showPhotoLibrary: Bool = false
    @State private var showPhotoViewer: Bool = false
    @State private var viewerIndex: Int = 0
    @State private var showDeleteConfirm: Bool = false
    private var canAddPhoto: Bool { imagePaths.count < maxPhotos }
    private var remainingPhotoSlots: Int { max(0, maxPhotos - imagePaths.count) }

    var body: some View {
        ZStack {
            FigmaTheme.mutedBackground.ignoresSafeArea()
                .onTapGesture {
                    notesFocused = false
                    endEditingGlobal()
                }

            VStack(spacing: 0) {
                header
                content
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fullScreenCover(isPresented: $showCamera) {
            SystemCameraPicker(
                preferredDevice: .rear,
                mirrorOnCapture: mirrorSelfie,
                onImage: { image in
                    showCamera = false
                    appendCaptured(image)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker(
                selectionLimit: max(1, remainingPhotoSlots),
                onImages: { images in
                    showPhotoLibrary = false
                    appendPhotosFromLibrary(images)
                },
                onCancel: { showPhotoLibrary = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            PhotoViewer(
                imagePaths: imagePaths,
                userID: userID,
                startIndex: viewerIndex,
                onClose: { showPhotoViewer = false }
            )
        }
        .alert(L10n.t("delete_memory_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("delete"), role: .destructive) {
                onDelete?()
            }
        } message: {
            Text(L10n.t("delete_memory_confirm_message"))
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                MemoryNotesEditor(text: $notes, isFocused: $notesFocused, placeholder: L10n.t("memory_notes_placeholder"))
                    .frame(minHeight: 188, maxHeight: 240)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)

                if !imagePaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(imagePaths.enumerated()), id: \.offset) { idx, p in
                                ZStack(alignment: .topTrailing) {
                                    PhotoThumb(path: p, userID: userID)
                                        .onTapGesture {
                                            viewerIndex = idx
                                            showPhotoViewer = true
                                        }

                                    Button {
                                        let removed = imagePaths.remove(at: idx)
                                        PhotoStore.delete(named: removed, userID: userID)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(FigmaTheme.text.opacity(0.6))
                                            .background(Color.white.opacity(0.75).clipShape(Circle()))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(minHeight: 290)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .onTapGesture {
                notesFocused = false
                endEditingGlobal()
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 12) {
                Button { showCamera = true } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canAddPhoto)
                .opacity(canAddPhoto ? 1 : 0.35)

                Button { showPhotoLibrary = true } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canAddPhoto)
                .opacity(canAddPhoto ? 1 : 0.35)
            }
            Spacer()

            Button(action: onSave) {
                Text(L10n.t("save").uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .frame(height: 48)
                    .background(UITheme.accent)
                    .clipShape(Capsule(style: .continuous))
                    .shadow(color: UITheme.accent.opacity(0.22), radius: 10, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(isNew ? L10n.key("add_memory") : L10n.key("edit_memory"))
                .appHeaderStyle()
                .foregroundColor(FigmaTheme.text)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if onDelete != nil {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .background(Color.white)
    }

    private func appendCaptured(_ image: UIImage) {
        guard canAddPhoto else { return }
        if let filename = try? PhotoStore.saveJPEG(image, userID: userID) {
            imagePaths.append(filename)
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: nil)
        }
    }

    private func appendPhotosFromLibrary(_ images: [UIImage]) {
        guard canAddPhoto else { return }
        for image in images {
            if !canAddPhoto { break }
            if let filename = try? PhotoStore.saveJPEG(image, userID: userID) {
                imagePaths.append(filename)
            }
        }
    }
}


// =======================================================
// MARK: - Photo Viewer
// =======================================================

struct PhotoViewer: View {
    let imagePaths: [String]
    let userID: String
    let startIndex: Int
    let onClose: () -> Void

    @State private var index: Int

    init(imagePaths: [String], userID: String, startIndex: Int, onClose: @escaping () -> Void) {
        self.imagePaths = imagePaths
        self.userID = userID
        self.startIndex = startIndex
        self.onClose = onClose
        _index = State(initialValue: max(0, min(startIndex, imagePaths.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !imagePaths.isEmpty {
                TabView(selection: $index) {
                    ForEach(Array(imagePaths.enumerated()), id: \.offset) { i, p in
                        ZoomableImage(path: p, userID: userID)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("\(index + 1)/\(max(1, imagePaths.count))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
            }
        }
    }
}

private struct ZoomableImage: View {
    let path: String
    let userID: String

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        Group {
            if let img = PhotoStore.loadImage(named: path, userID: userID) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in
                                scale = max(1, min(4, lastScale * v))
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        if scale > 1 { scale = 1; lastScale = 1 }
                        else { scale = 2; lastScale = 2 }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
    }
}


struct MemoryGroupDetailPage: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    let memories: [JourneyMemory]
    @Binding var isPresented: Bool
    let onOpenDetail: (JourneyMemory) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.key("tab_memory"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)

                    Spacer()

                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(memories.enumerated()), id: \.element.id) { idx, mem in
                            Button {
                                onOpenDetail(mem)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    if !mem.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(mem.notes)
                                            .font(.system(size: 14))
                                            .foregroundColor(FigmaTheme.text.opacity(0.85))
                                            .lineLimit(4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else if !mem.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(mem.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(FigmaTheme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(L10n.key("empty_memory"))
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    if !mem.imagePaths.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(mem.imagePaths.prefix(6), id: \.self) { p in
                                                    if let img = PhotoStore.loadImage(named: p, userID: sessionStore.currentUserID) {
                                                        Image(uiImage: img)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 64, height: 64)
                                                            .clipped()
                                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }

                                    Text(mem.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if idx < memories.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: 340, maxHeight: 520)
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
}



// =======================================================
// MARK: - MKMapView bridge (for consistent map label localization)
// =======================================================

final class JourneyMapController: ObservableObject {
    enum Kind {
        case setCamera(center: CLLocationCoordinate2D, distance: CLLocationDistance, heading: CLLocationDirection, pitch: CGFloat)
        case setRegion(MKCoordinateRegion)
        case fit(rect: MKMapRect, edgePadding: UIEdgeInsets)
    }

    struct Command {
        let id: UUID = UUID()
        let kind: Kind
    }

    @Published var command: Command? = nil

    func setCamera(center: CLLocationCoordinate2D, distance: CLLocationDistance, heading: CLLocationDirection, pitch: CGFloat) {
        command = Command(kind: .setCamera(center: center, distance: distance, heading: heading, pitch: pitch))
    }

    func setRegion(_ region: MKCoordinateRegion) {
        command = Command(kind: .setRegion(region))
    }

    func fit(coordinates: [CLLocationCoordinate2D], edgePadding: UIEdgeInsets = UIEdgeInsets(top: 80, left: 50, bottom: 220, right: 50)) {
        guard coordinates.count >= 2 else { return }
        var rect = MKMapRect.null
        for c in coordinates {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        command = Command(kind: .fit(rect: rect, edgePadding: edgePadding))
    }
}

private final class MemoryGroupAnnotation: NSObject, MKAnnotation {
    let key: String
    dynamic var coordinate: CLLocationCoordinate2D
    let items: [JourneyMemory]

    init(key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory]) {
        self.key = key
        self.coordinate = coordinate
        self.items = items
    }
}

private final class RobotAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var face: RobotFace
    var headingDegrees: Double

    init(coordinate: CLLocationCoordinate2D, face: RobotFace, headingDegrees: Double) {
        self.coordinate = coordinate
        self.face = face
        self.headingDegrees = headingDegrees
    }
}

private struct RobotMapMarkerView: View {
    let face: RobotFace
    let headingDegrees: Double
    let showsHeadlight: Bool

    var body: some View {
        ZStack {
            if showsHeadlight {
                AvatarHeadlightConeView(headingDegrees: headingDegrees)
            }
            RobotRendererView(size: AvatarMapMarkerStyle.visualSize, face: face, loadout: AvatarLoadoutStore.load())
        }
        .frame(width: AvatarMapMarkerStyle.annotationSize, height: AvatarMapMarkerStyle.annotationSize)
    }
}

private struct JourneyMKMapView: UIViewRepresentable {
    @ObservedObject var controller: JourneyMapController
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue

    let userCoordinate: CLLocationCoordinate2D?
    let headingDegrees: Double
    let headlightEnabled: Bool
    let travelMode: TravelMode

    let segments: [RenderRouteSegment]
    let liveTail: [CLLocationCoordinate2D]
    let memoryGroups: [(key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory])]

    @Binding var cameraDistance: CLLocationDistance
    @Binding var followUser: Bool
    @Binding var isUserInteracting: Bool

    let onSelectMemories: ([JourneyMemory]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        applyAppearance(on: map)
        map.pointOfInterestFilter = .excludingAll
        map.showsTraffic = false

        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "robot")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "memoryGroup")

        // Gesture detection to match previous SwiftUI modifier behavior
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onUserGesture(_:)))
        pan.cancelsTouchesInView = false
        map.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onUserGesture(_:)))
        pinch.cancelsTouchesInView = false
        map.addGestureRecognizer(pinch)

        context.coordinator.ensureRobotAnnotation(on: map, coord: userCoordinate, heading: headingDegrees)
        context.coordinator.syncOverlays(on: map, segments: segments, liveTail: liveTail)
        context.coordinator.syncMemoryAnnotations(on: map, groups: memoryGroups)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        applyAppearance(on: map)

        if let cmd = controller.command, cmd.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = cmd.id
            context.coordinator.apply(cmd.kind, to: map)
        }

        context.coordinator.ensureRobotAnnotation(on: map, coord: userCoordinate, heading: headingDegrees)
        context.coordinator.syncOverlays(on: map, segments: segments, liveTail: liveTail)
        context.coordinator.syncMemoryAnnotations(on: map, groups: memoryGroups)

        // Keep cameraDistance roughly in sync
        let d = map.camera.altitude
        if abs(d - cameraDistance) > 1 {
            DispatchQueue.main.async { cameraDistance = d }
        }
    }

    // MARK: - Coordinator

    private func applyAppearance(on map: MKMapView) {
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle(for: mapAppearanceRaw)
        map.mapType = MapAppearanceSettings.mapType(for: mapAppearanceRaw)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: JourneyMKMapView
        var lastCommandID: UUID? = nil

        private var robotAnnotation: RobotAnnotation? = nil
        private var memoryAnnotationsByKey: [String: MemoryGroupAnnotation] = [:]

        private var lastSegmentsSignature: String = ""
        private var lastTailSignature: String = ""
        private var isProgrammaticRegionChange = false

        init(_ parent: JourneyMKMapView) {
            self.parent = parent
        }

        @objc func onUserGesture(_ gr: UIGestureRecognizer) {
            if gr.state == .began || gr.state == .changed {
                parent.followUser = false
                parent.isUserInteracting = true
            } else if gr.state == .ended || gr.state == .cancelled || gr.state == .failed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.parent.isUserInteracting = false
                }
            }
        }

        func apply(_ kind: JourneyMapController.Kind, to map: MKMapView) {
            isProgrammaticRegionChange = true
            switch kind {
            case let .setCamera(center, distance, heading, pitch):
                let cam = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: pitch, heading: heading)
                map.setCamera(cam, animated: true)

            case let .setRegion(region):
                map.setRegion(region, animated: true)

            case let .fit(rect, edgePadding):
                map.setVisibleMapRect(rect, edgePadding: edgePadding, animated: true)
            }
        }

        func ensureRobotAnnotation(on map: MKMapView, coord: CLLocationCoordinate2D?, heading: Double) {
            guard let coord else {
                if let existing = robotAnnotation {
                    map.removeAnnotation(existing)
                    robotAnnotation = nil
                }
                return
            }

            let h = normalizedHeading(heading)
            if let existing = robotAnnotation {
                existing.coordinate = coord
                if headingDelta(existing.headingDegrees, h) >= 2 {
                    existing.headingDegrees = h
                    if let view = map.view(for: existing) {
                        configureRobotAnnotationView(
                            view,
                            face: existing.face,
                            worldHeading: h,
                            cameraHeading: map.camera.heading
                        )
                    }
                }
            } else {
                let ann = RobotAnnotation(coordinate: coord, face: .front, headingDegrees: h)
                robotAnnotation = ann
                map.addAnnotation(ann)
            }
        }

        private func normalizedHeading(_ raw: Double) -> Double {
            let h = raw.truncatingRemainder(dividingBy: 360)
            return h >= 0 ? h : (h + 360)
        }

        private func headingDelta(_ a: Double, _ b: Double) -> Double {
            let d = abs(normalizedHeading(a) - normalizedHeading(b))
            return min(d, 360 - d)
        }

        private func configureRobotAnnotationView(
            _ view: MKAnnotationView,
            face: RobotFace,
            worldHeading: Double,
            cameraHeading: Double
        ) {
            view.canShowCallout = false
            view.bounds = CGRect(
                x: 0,
                y: 0,
                width: AvatarMapMarkerStyle.annotationSize,
                height: AvatarMapMarkerStyle.annotationSize
            )
            view.backgroundColor = .clear
            view.centerOffset = .zero
            view.displayPriority = .required
            view.collisionMode = .circle
            if #available(iOS 14.0, *) {
                view.zPriority = .min
            }

            let displayHeading = normalizedHeading(worldHeading - cameraHeading)
            let hosting = UIHostingController(
                rootView: RobotMapMarkerView(
                    face: face,
                    headingDegrees: displayHeading,
                    showsHeadlight: parent.headlightEnabled
                )
            )
            hosting.view.backgroundColor = .clear
            hosting.view.frame = view.bounds

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)
        }

        func syncMemoryAnnotations(on map: MKMapView, groups: [(key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory])]) {
            func itemsSignature(_ items: [JourneyMemory]) -> String {
                items
                    .sorted { $0.id < $1.id }
                    .map { m in
                        let t = m.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let n = m.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        return "\(m.id)|t:\(t.count)|n:\(n.count)|p:\(m.imagePaths.count)"
                    }
                    .joined(separator: ";")
            }

            let newKeys = Set(groups.map(\.key))
            let oldKeys = Set(memoryAnnotationsByKey.keys)

            // Remove
            for k in oldKeys.subtracting(newKeys) {
                if let ann = memoryAnnotationsByKey.removeValue(forKey: k) {
                    map.removeAnnotation(ann)
                }
            }

            // Add / update
            for g in groups {
                if let ann = memoryAnnotationsByKey[g.key] {
                    ann.coordinate = g.coordinate
                    // ✅ Replace annotation not only when count changes, but also when content changes.
                    // Otherwise tapping the pin may show stale notes/title until app relaunch.
                    if ann.items.count != g.items.count || itemsSignature(ann.items) != itemsSignature(g.items) {
                        map.removeAnnotation(ann)
                        let newAnn = MemoryGroupAnnotation(key: g.key, coordinate: g.coordinate, items: g.items)
                        memoryAnnotationsByKey[g.key] = newAnn
                        map.addAnnotation(newAnn)
                    }
                } else {
                    let ann = MemoryGroupAnnotation(key: g.key, coordinate: g.coordinate, items: g.items)
                    memoryAnnotationsByKey[g.key] = ann
                    map.addAnnotation(ann)
                }
            }
        }

        private func signature(for segments: [RenderRouteSegment], tail: [CLLocationCoordinate2D]) -> (String, String) {
            let segSig = segments.map { "\($0.id):\($0.style.rawValue):\($0.coords.count)" }.joined(separator: "|")
            let tailSig = tail.map { "\(Int($0.latitude*1e5)):\(Int($0.longitude*1e5))" }.joined(separator: "|")
            return (segSig, tailSig)
        }

        private func segmentSignature(_ coords: [CLLocationCoordinate2D]) -> String {
            guard let first = coords.first, let last = coords.last else { return UUID().uuidString }
            let stride = max(1, coords.count / 6)
            var samples: [CLLocationCoordinate2D] = [first]
            if coords.count > 2 {
                var i = stride
                while i < coords.count - 1 {
                    samples.append(coords[i])
                    i += stride
                }
            }
            samples.append(last)

            func q(_ c: CLLocationCoordinate2D) -> String {
                let lat = Int((c.latitude * 2_000).rounded())
                let lon = Int((c.longitude * 2_000).rounded())
                return "\(lat):\(lon)"
            }

            let forward = samples.map(q).joined(separator: "|")
            let backward = samples.reversed().map(q).joined(separator: "|")
            return min(forward, backward)
        }

        private func quantile(_ values: [Int], p: Double) -> Double {
            guard !values.isEmpty else { return 1.0 }
            let sorted = values.sorted()
            let index = Int((Double(sorted.count - 1) * p).rounded())
            return Double(sorted[max(0, min(sorted.count - 1, index))])
        }

        func syncOverlays(on map: MKMapView, segments: [RenderRouteSegment], liveTail: [CLLocationCoordinate2D]) {
            let (segSig, tailSig) = signature(for: segments, tail: liveTail)
            let needsSegUpdate = (segSig != lastSegmentsSignature)
            let needsTailUpdate = (tailSig != lastTailSignature)

            guard needsSegUpdate || needsTailUpdate else { return }

            // Remove old route overlays (keep any unrelated overlays)
            let keep = map.overlays.filter { ov in
                guard let shape = ov as? MKShape, let t = shape.title else { return true }
                return !(t.hasPrefix("route_") || t == "tail")
            }
            map.removeOverlays(map.overlays)
            map.addOverlays(keep)

            var counts: [String: Int] = [:]
            for seg in segments where seg.style != .dashed && seg.coords.count >= 2 {
                let sig = segmentSignature(seg.coords)
                counts[sig, default: 0] += 1
            }
            let p95 = max(1.0, quantile(Array(counts.values), p: 0.95))

            for seg in segments where seg.coords.count > 1 {
                let poly = WeightedRoutePolyline(coordinates: seg.coords, count: seg.coords.count)
                poly.isGap = (seg.style == .dashed)
                if let n = counts[segmentSignature(seg.coords)], !poly.isGap {
                    poly.repeatWeight = min(1.0, log(1.0 + Double(n)) / log(1.0 + p95))
                } else {
                    poly.repeatWeight = 0.0
                }
                poly.title = poly.isGap ? "route_dashed" : "route_solid"
                map.addOverlay(poly)
            }

            if liveTail.count == 2 {
                let poly = MKPolyline(coordinates: liveTail, count: liveTail.count)
                poly.title = "tail"
                map.addOverlay(poly)
            }

            lastSegmentsSignature = segSig
            lastTailSignature = tailSig
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }

            // widths comparable to SwiftUI version
            func widths(for distance: CLLocationDistance, mode: TravelMode) -> CGFloat {
                // MapKit camera altitude grows as you zoom OUT.
                // We want strokes to become THINNER when zooming out (and never explode in width).
                let d = max(500.0, distance)
                let t = max(0.55, min(1.90, 1200.0 / d))
                var core = 6 * t
                switch mode {
                case .walk, .run: core *= 1.10
                case .transit: core *= 0.82
                case .bike: core *= 1.05
                case .motorcycle: core *= 1.10
                case .drive: core *= 1.18
                case .flight: core *= 1.05
                case .unknown: core *= 1.00
                }
                return core
            }

            if poly.title == "tail" {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.strokeColor = MapAppearanceSettings.routeBaseColor.withAlphaComponent(0.35)
                renderer.lineWidth = 3
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            let base = MapAppearanceSettings.routeBaseColor
            let coreWidth = widths(for: mapView.camera.altitude, mode: parent.travelMode)
            guard let styled = poly as? WeightedRoutePolyline else {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.lineWidth = coreWidth
                renderer.lineCap = .round
                renderer.lineJoin = .round
                renderer.strokeColor = base.withAlphaComponent(0.50)
                if poly.title == "route_dashed" {
                    renderer.lineDashPattern = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }
                }
                return renderer
            }

            let isGap = styled.isGap
            let weight = CGFloat(max(0, min(1, styled.repeatWeight)))

            let halo = MKPolylineRenderer(polyline: styled)
            halo.lineWidth = isGap ? max(1.2, coreWidth * 0.6) : (coreWidth * 0.95 + weight * 1.1)
            halo.lineCap = CGLineCap.round
            halo.lineJoin = CGLineJoin.round
            halo.strokeColor = base.withAlphaComponent(isGap ? 0.08 : 0.12)
            if isGap {
                halo.lineDashPattern = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }
            }

            let freq = MKPolylineRenderer(polyline: styled)
            freq.lineWidth = isGap ? 0 : (coreWidth * 0.82 + weight * 0.95)
            freq.lineCap = CGLineCap.round
            freq.lineJoin = CGLineJoin.round
            freq.strokeColor = base.withAlphaComponent(isGap ? 0 : (0.05 + 0.15 * weight))

            let core = MKPolylineRenderer(polyline: styled)
            core.lineWidth = isGap ? max(0.9, coreWidth * 0.46) : (coreWidth * 0.64 + weight * 0.52)
            core.lineCap = CGLineCap.round
            core.lineJoin = CGLineJoin.round
            core.strokeColor = base.withAlphaComponent(isGap ? 0.30 : 0.84)
            if isGap {
                core.lineDashPattern = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }
            }

            return MultiPolylineRenderer(renderers: [halo, freq, core])
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    if let ann = annotation as? RobotAnnotation {
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "robot", for: ann)
        configureRobotAnnotationView(
            view,
            face: ann.face,
            worldHeading: ann.headingDegrees,
            cameraHeading: mapView.camera.heading
        )
        return view
    }

if let ann = annotation as? MemoryGroupAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "memoryGroup", for: ann)
                view.canShowCallout = false
                view.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
                view.backgroundColor = .clear
                view.displayPriority = .required
                if #available(iOS 14.0, *) {
                    view.zPriority = .max
                }

                let hosting = UIHostingController(rootView: MemoryPin(cluster: ann.items))
                hosting.view.backgroundColor = .clear
                hosting.view.frame = view.bounds

                view.subviews.forEach { $0.removeFromSuperview() }
                view.addSubview(hosting.view)
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    if let ann = view.annotation as? RobotAnnotation {
        // cycle 90° per tap: front -> right -> back -> left -> front
        switch ann.face {
        case .front: ann.face = .right
        case .right: ann.face = .back
        case .back: ann.face = .left
        case .left: ann.face = .front
        }

        configureRobotAnnotationView(
            view,
            face: ann.face,
            worldHeading: ann.headingDegrees,
            cameraHeading: mapView.camera.heading
        )
        mapView.deselectAnnotation(ann, animated: false)
        return
    }

    if let ann = view.annotation as? MemoryGroupAnnotation {
        parent.onSelectMemories(ann.items)
        mapView.deselectAnnotation(ann, animated: false)
    }
}

private final class WeightedRoutePolyline: MKPolyline {
    var isGap: Bool = false
    var repeatWeight: Double = 0
}

private final class MultiPolylineRenderer: MKOverlayRenderer {
    private let renderers: [MKOverlayPathRenderer]

    init(renderers: [MKOverlayPathRenderer]) {
        self.renderers = renderers
        super.init(overlay: renderers.first?.overlay ?? MKPolyline())
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        for r in renderers {
            r.draw(mapRect, zoomScale: zoomScale, in: context)
        }
    }
}

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isProgrammaticRegionChange {
                parent.followUser = false
                parent.isUserInteracting = true
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange { isProgrammaticRegionChange = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.parent.isUserInteracting = false
            }
        }
    }
}
