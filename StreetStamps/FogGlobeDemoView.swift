//
//  FogGlobeDemoView.swift
//  StreetStamps
//
//  DEBUG-only sandbox to verify the pre-rendered fog bitmap approach
//  shows no flicker when the user pans / zooms the globe.
//

#if DEBUG

import SwiftUI
import CoreLocation

struct FogGlobeDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fogBitmap: CGImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let bitmap = fogBitmap {
                FogGlobeView(fogBitmap: bitmap)
                    .ignoresSafeArea()
            } else {
                ProgressView("Rendering fog bitmap…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 18)
                }
                Spacer()
            }
        }
        .task {
            await renderBitmap()
        }
    }

    private func renderBitmap() async {
        let runs = Self.demoRoutes
        let bitmap: CGImage? = await Task.detached(priority: .userInitiated) {
            FogBitmapGenerator.render(coordRuns: runs)
        }.value
        await MainActor.run {
            self.fogBitmap = bitmap
        }
    }

    /// Hardcoded long-distance route-shaped paths — visually distinct on the globe,
    /// no GCJ-02 concerns (all outside mainland China). At 4096-px bitmap, brush is
    /// ≈6 km wide, so paths must span hundreds of km to clearly read as "routes"
    /// instead of dots.
    private static let demoRoutes: [[CLLocationCoordinate2D]] = [
        // US East Coast: Boston → New York → Philadelphia → Washington DC (~700 km)
        densify([
            (42.36, -71.06),   // Boston
            (41.77, -72.67),   // Hartford
            (40.78, -73.97),   // New York
            (40.22, -74.76),   // Trenton
            (39.95, -75.16),   // Philadelphia
            (39.29, -76.61),   // Baltimore
            (38.91, -77.04)    // Washington DC
        ]),
        // Europe: London → Brussels → Amsterdam → Berlin (~1000 km)
        densify([
            (51.51, -0.13),    // London
            (50.85,  4.35),    // Brussels
            (52.37,  4.90),    // Amsterdam
            (52.52, 13.40)     // Berlin
        ]),
        // Japan: Tokyo → Nagoya → Kyoto → Osaka → Hiroshima (~800 km)
        densify([
            (35.68, 139.77),   // Tokyo
            (35.36, 138.73),   // Mt Fuji
            (35.18, 136.91),   // Nagoya
            (35.01, 135.77),   // Kyoto
            (34.69, 135.50),   // Osaka
            (34.39, 132.46)    // Hiroshima
        ]),
        // Australia East: Sydney → Canberra → Melbourne (~900 km)
        densify([
            (-33.87, 151.21),  // Sydney
            (-35.28, 149.13),  // Canberra
            (-36.72, 144.28),  // Bendigo
            (-37.81, 144.96)   // Melbourne
        ])
    ]

    /// Insert intermediate points so each segment has ≥1 sample per ~25 km.
    /// Keeps the stroked path smooth on a 4096-px globe.
    private static func densify(_ waypoints: [(Double, Double)]) -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else {
            return waypoints.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        }
        var out: [CLLocationCoordinate2D] = []
        for i in 0..<(waypoints.count - 1) {
            let a = waypoints[i]
            let b = waypoints[i + 1]
            // Approximate degree → km: 1° lat ≈ 111 km
            let dLat = (b.0 - a.0) * 111
            let dLon = (b.1 - a.1) * 111 * cos(a.0 * .pi / 180)
            let segKm = (dLat * dLat + dLon * dLon).squareRoot()
            let steps = max(1, Int(segKm / 25))
            for s in 0..<steps {
                let t = Double(s) / Double(steps)
                out.append(CLLocationCoordinate2D(
                    latitude:  a.0 + (b.0 - a.0) * t,
                    longitude: a.1 + (b.1 - a.1) * t
                ))
            }
        }
        out.append(CLLocationCoordinate2D(latitude: waypoints.last!.0, longitude: waypoints.last!.1))
        return out
    }
}

#endif
