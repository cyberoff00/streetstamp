import SwiftUI
import UIKit

/// Export-only rendering for long image share.
/// Designed to be deterministic: loads images from local disk via PhotoStore.
struct MemoryDetailExportView: View {
    let journey: JourneyRoute
    let memories: [JourneyMemory]
    let cityName: String
    let countryName: String
    let userID: String

    private var journeyDate: String {
        let d = journey.startTime ?? memories.map(\.timestamp).min() ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: d).uppercased()
    }

    private var distanceText: String {
        let km = journey.distance / 1000.0
        return String(format: "%.1fkm", km)
    }

    private var durationText: String {
        guard let start = journey.startTime, let end = journey.endTime else {
            return "--:--:--"
        }
        let seconds = Int(end.timeIntervalSince(start))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(cityName.uppercased())
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.black)

                Text("\(countryName.uppercased()) • \(journeyDate)")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(.gray)
            }

            // Stats
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key("lockscreen_distance"))
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.gray)
                    Text(distanceText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key("lockscreen_duration"))
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(.gray)
                    Text(durationText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
            }

            Divider().opacity(0.25)

            // Memories timeline
            let tf: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "h:mm a"
                return f
            }()

            ForEach(memories.sorted(by: { $0.timestamp < $1.timestamp })) { mem in
                VStack(alignment: .leading, spacing: 10) {
                    Text(tf.string(from: mem.timestamp).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.gray)

                    let notes = mem.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = mem.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = !notes.isEmpty ? notes : (!title.isEmpty ? title : "-")

                    Text(text)
                        .font(.system(size: 15))
                        .foregroundColor(.black.opacity(0.88))

                    if !mem.imagePaths.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(mem.imagePaths, id: \.self) { filename in
                                if let ui = PhotoStore.loadImage(named: filename, userID: userID) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 260)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 10)

                if mem.id != memories.sorted(by: { $0.timestamp < $1.timestamp }).last?.id {
                    Divider().opacity(0.15)
                }
            }

            Text("— StreetStamps")
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.9))
                .padding(.top, 8)
        }
        .padding(16)
        .background(Color.white)
    }
}
import SwiftUI
import UIKit

enum MemoryExportRenderer {

    /// Render the journey memory detail into a single long UIImage.
    /// - Note: iOS 16+ only (ImageRenderer).
    @MainActor
    static func renderLongImage(
        journey: JourneyRoute,
        memories: [JourneyMemory],
        cityName: String,
        countryName: String,
        userID: String
    ) -> UIImage? {

        guard #available(iOS 16.0, *) else { return nil }

        // Logical width * scale -> export pixel width.
        // 360 @ 3x ≈ 1080px, clear enough for sharing.
        let exportWidth: CGFloat = 360

        let view = MemoryDetailExportView(
            journey: journey,
            memories: memories,
            cityName: cityName,
            countryName: countryName,
            userID: userID
        )
        .frame(width: exportWidth)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = .init(width: exportWidth, height: nil)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
