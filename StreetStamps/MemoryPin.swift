import SwiftUI
import UIKit
import CoreLocation

enum MemoryPinStyle {
    static let accentGreen = Color(red: 0.30, green: 0.85, blue: 0.45)
}

enum MemoryClusterer {
    struct Cluster: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let items: [JourneyMemory]
        var key: String { id }
    }

    static func cluster(
        _ entries: [(memory: JourneyMemory, coordinate: CLLocationCoordinate2D)],
        thresholdMeters: CLLocationDistance = 20
    ) -> [Cluster] {
        let sorted = entries.sorted { $0.memory.timestamp < $1.memory.timestamp }
        var result: [Cluster] = []
        for entry in sorted {
            if let idx = result.firstIndex(where: { meters($0.coordinate, entry.coordinate) <= thresholdMeters }) {
                let merged = Cluster(
                    id: result[idx].id,
                    coordinate: result[idx].coordinate,
                    items: result[idx].items + [entry.memory]
                )
                result[idx] = merged
            } else {
                result.append(Cluster(
                    id: "cluster_\(entry.memory.id)",
                    coordinate: entry.coordinate,
                    items: [entry.memory]
                ))
            }
        }
        return result
    }

    private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

struct MemoryPin: View {
    let cluster: [JourneyMemory]
    var isCompact: Bool = false

    var body: some View {
        if isCompact {
            Circle()
                .fill(MemoryPinStyle.accentGreen)
                .frame(width: 10, height: 10)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        } else {
            let hasPhoto = cluster.contains { !$0.imagePaths.isEmpty }
            let hasNote = cluster.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let count = cluster.count
            let allPending = cluster.allSatisfy { $0.locationStatus == .pending }

            ZStack {
                Circle()
                    .fill(MemoryPinStyle.accentGreen)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                ZStack {
                    if allPending {
                        // Pending: GPS is resolving
                        Image(systemName: "location.slash")
                            .font(.system(size: 14, weight: .semibold))
                    } else if hasPhoto && hasNote {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .offset(x: 6, y: 0)

                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .offset(x: -6, y: 0)
                    } else if hasPhoto {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(.black.opacity(0.78))

                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Circle().fill(Color.black))
                        .offset(x: 12, y: -12)
                }
            }
            .opacity(allPending ? 0.55 : 1.0)
        }
    }
}

struct MemoryClusterPickerSheet: View {
    let memories: [JourneyMemory]
    let userID: String
    @Binding var isPresented: Bool
    let onSelect: (JourneyMemory) -> Void

    private var sorted: [JourneyMemory] {
        memories.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sorted) { memory in
                    Button {
                        onSelect(memory)
                        isPresented = false
                    } label: {
                        MemoryClusterPickerRow(memory: memory, userID: userID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle(L10n.t("memory_picker_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("cancel")) { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct MemoryClusterPickerRow: View {
    let memory: JourneyMemory
    let userID: String
    @State private var localThumb: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .task(id: memory.id) {
            guard localThumb == nil, let path = memory.imagePaths.first else { return }
            let uid = userID
            let p = path
            let loaded = await Task.detached(priority: .userInitiated) {
                PhotoStore.loadImage(named: p, userID: uid)
            }.value
            guard !Task.isCancelled else { return }
            localThumb = loaded
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let img = localThumb {
            Image(uiImage: img).resizable().scaledToFill()
        } else if memory.imagePaths.first != nil {
            placeholder
        } else if let urlString = memory.remoteImageURLs.first, let url = URL(string: urlString) {
            CachedRemoteImage(url: url) { $0.resizable() } placeholder: {
                placeholder
            } failure: {
                placeholder
            }
            .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(red: 0.94, green: 0.95, blue: 0.96)
            Image(systemName: hasNote ? "pencil" : "photo")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    private var hasNote: Bool {
        !memory.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var subtitle: String {
        let trimmedNote = memory.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty { return trimmedNote }
        let trimmedTitle = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        return L10n.t("memory_picker_no_note")
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = LanguagePreference.shared.displayLocale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: memory.timestamp)
    }
}
