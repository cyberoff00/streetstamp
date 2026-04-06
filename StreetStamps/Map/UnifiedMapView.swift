import SwiftUI
import MapKit

/// A single map view that delegates to either MapKit or Mapbox based on user's layer style choice.
struct UnifiedMapView: View {
    @AppStorage(MapLayerStyle.storageKey) private var layerRaw = MapLayerStyle.current.rawValue

    let segments: [MapRouteSegment]
    let annotations: [MapAnnotationItem]
    let circles: [MapCircleOverlay]
    let cameraCommand: MapCameraCommand?
    let config: MapConfiguration
    let callbacks: MapCallbacks

    init(
        segments: [MapRouteSegment],
        annotations: [MapAnnotationItem] = [],
        circles: [MapCircleOverlay] = [],
        cameraCommand: MapCameraCommand? = nil,
        config: MapConfiguration,
        callbacks: MapCallbacks = MapCallbacks()
    ) {
        self.segments = segments
        self.annotations = annotations
        self.circles = circles
        self.cameraCommand = cameraCommand
        self.config = config
        self.callbacks = callbacks
    }

    private var layerStyle: MapLayerStyle {
        MapLayerStyle(rawValue: layerRaw) ?? .mutedDark
    }

    var body: some View {
        switch layerStyle.engine {
        case .mapkit:
            MapKitEngineView(
                segments: segments,
                annotations: annotations,
                circles: circles,
                cameraCommand: cameraCommand,
                config: config,
                callbacks: callbacks,
                layerStyle: layerStyle
            )
        case .mapbox:
            MapboxEngineView(
                segments: segments,
                annotations: annotations,
                circles: circles,
                cameraCommand: cameraCommand,
                config: config,
                callbacks: callbacks,
                layerStyle: layerStyle
            )
        }
    }
}
