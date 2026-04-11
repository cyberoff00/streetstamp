//
//  FogGlobeView.swift
//  StreetStamps
//
//  MapKit-based globe view with fog-of-war overlay.
//  Receives a pre-rendered CGImage; MKOverlayRenderer.draw() blits from it
//  synchronously — no tile loading, no flicker.
//

import SwiftUI
import MapKit
import CoreGraphics

struct FogGlobeView: UIViewRepresentable {
    let fogBitmap: CGImage?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()

        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        } else {
            map.mapType = .hybrid
        }

        map.setCamera(
            MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                fromDistance: 20_000_000,
                pitch: 0,
                heading: 0
            ),
            animated: false
        )

        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.delegate = context.coordinator

        applyOverlay(map: map, bitmap: fogBitmap, coordinator: context.coordinator)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Only swap when the bitmap identity changes
        let newID = fogBitmap.map { ObjectIdentifier($0 as AnyObject) }
        guard newID != context.coordinator.lastBitmapID else { return }
        applyOverlay(map: map, bitmap: fogBitmap, coordinator: context.coordinator)
    }

    private func applyOverlay(map: MKMapView, bitmap: CGImage?, coordinator: Coordinator) {
        // Remove old overlay
        if let old = coordinator.overlay {
            map.removeOverlay(old)
        }

        let overlay = FogMapOverlay()
        coordinator.overlay = overlay
        coordinator.currentBitmap = bitmap
        coordinator.lastBitmapID = bitmap.map { ObjectIdentifier($0 as AnyObject) }

        map.addOverlay(overlay, level: .aboveLabels)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var overlay: FogMapOverlay?
        var currentBitmap: CGImage?
        var lastBitmapID: ObjectIdentifier?

        func mapView(_ map: MKMapView,
                     rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FogMapOverlay {
                if let bitmap = currentBitmap {
                    return FogOverlayRenderer(
                        overlay: overlay,
                        fogBitmap: bitmap,
                        fogColor: FogBitmapGenerator.defaultFogColor
                    )
                } else {
                    // No bitmap yet — solid fog (will be replaced when bitmap arrives)
                    let renderer = MKOverlayRenderer(overlay: overlay)
                    return renderer
                }
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
