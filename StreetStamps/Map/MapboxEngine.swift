import SwiftUI
import MapboxMaps
import Turf
import CoreLocation
import MapKit

// MARK: - Mapbox Engine UIViewRepresentable

struct MapboxEngineView: UIViewRepresentable {
    let segments: [MapRouteSegment]
    let annotations: [MapAnnotationItem]
    let circles: [MapCircleOverlay]
    /// Mapbox engine accepts the brush param for API symmetry but does not yet
    /// implement an interactive brush. Mask filtering is upstream (segments
    /// are pre-filtered) so polylines still respect the user's existing mask.
    let eraseBrush: MapEraseBrush?
    let cameraCommand: MapCameraCommand?
    let config: MapConfiguration
    let callbacks: MapCallbacks
    let layerStyle: MapLayerStyle

    // Source/layer IDs
    private let routeSourceId = "um-routes-source"
    private let routeGlowLayerId = "um-routes-glow"
    private let routeMainLayerId = "um-routes-main"
    private let routeHighlightLayerId = "um-routes-highlight"
    private let routeDashedMainLayerId = "um-routes-dashed-main"
    private let tailSourceId = "um-tail-source"
    private let tailLayerId = "um-tail-line"
    private let circleSourceId = "um-circles-source"
    private let circleGlowLayerId = "um-circles-glow"
    private let circleMainLayerId = "um-circles-main"
    let brushSourceId = "um-brush-source"
    let brushLayerId = "um-brush-circle"

    func makeCoordinator() -> Coordinator { Coordinator(config: config, callbacks: callbacks) }

    func makeUIView(context: Context) -> MapboxMaps.MapView {
        let mapView = MapboxMaps.MapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

        // Gesture config
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.panEnabled = true
        mapView.gestures.options.pinchEnabled = true
        mapView.gestures.options.doubleTapToZoomInEnabled = true
        mapView.gestures.options.doubleTouchToZoomOutEnabled = true
        mapView.gestures.options.quickZoomEnabled = true

        // Hide ornaments
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        context.coordinator.mapView = mapView
        context.coordinator.engineView = self

        // Load style — v11: loadStyle with (Error?) completion
        let styleURI = StyleURI(rawValue: layerStyle.mapboxStyleURI) ?? .dark
        context.coordinator.currentLayerStyle = layerStyle
        mapView.mapboxMap.loadStyle(styleURI) { error in
            if let error {
                print("[MapboxEngine] style load FAILED uri=\(layerStyle.mapboxStyleURI) error=\(error)")
                // Revert persisted selection so a bad style doesn't cause a crash loop on next launch
                MapLayerStyle.apply(.mutedDark)
                context.coordinator.currentLayerStyle = .mutedDark
                return
            }
            context.coordinator.styleLoaded = true
            context.coordinator.setupSourcesAndLayers()
            context.coordinator.refreshData()
            if let pending = context.coordinator.pendingCamera {
                context.coordinator.pendingCamera = nil
                context.coordinator.applyCamera(pending)
            }
        }

        // Camera change observation — v11: onCameraChanged.observe, store cancelable
        if config.isInteractive {
            let coordinator = context.coordinator
            let cancelable = mapView.mapboxMap.onCameraChanged.observe { _ in
                guard !coordinator.isProgrammaticCamera else { return }
                coordinator.callbacks.onFollowUserChanged?(false)
                coordinator.callbacks.onGestureStateChanged?(true)
                coordinator.scheduleGestureEnd()
                if coordinator.config.useZoomAwareVisibility {
                    coordinator.syncZoomAwareVisibility()
                }
            }
            context.coordinator.cameraChangedCancelable = cancelable

            // Eraser brush gesture recognizers. Both stay on the Mapbox view;
            // brushPan handles single-finger drags (and is enabled only in
            // brush mode), mapTwoFingerPan handles map panning while brush is
            // active (Mapbox's own pan is disabled then).
            let brushPan = ImmediatePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onBrushPan(_:)))
            brushPan.maximumNumberOfTouches = 1
            brushPan.cancelsTouchesInView = false
            brushPan.delegate = context.coordinator
            brushPan.isEnabled = false
            mapView.addGestureRecognizer(brushPan)
            context.coordinator.brushPanRecognizer = brushPan

            let twoPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onMapTwoFingerPan(_:)))
            twoPan.minimumNumberOfTouches = 2
            twoPan.maximumNumberOfTouches = 2
            twoPan.cancelsTouchesInView = false
            twoPan.delegate = context.coordinator
            twoPan.isEnabled = false
            mapView.addGestureRecognizer(twoPan)
            context.coordinator.mapTwoFingerPanRecognizer = twoPan
        }

        // Apply initial camera
        if let cmd = cameraCommand {
            context.coordinator.lastCommandID = cmd.id
            context.coordinator.applyCamera(cmd)
        }

        return mapView
    }

    func updateUIView(_ mapView: MapboxMaps.MapView, context: Context) {
        context.coordinator.config = config
        context.coordinator.callbacks = callbacks
        context.coordinator.engineView = self

        // Style switch when layer changes
        if context.coordinator.currentLayerStyle != layerStyle {
            let previousLayerStyle = context.coordinator.currentLayerStyle
            context.coordinator.currentLayerStyle = layerStyle
            context.coordinator.styleLoaded = false
            let styleURI = StyleURI(rawValue: layerStyle.mapboxStyleURI) ?? .dark
            mapView.mapboxMap.loadStyle(styleURI) { error in
                if let error {
                    print("[MapboxEngine] style reload FAILED uri=\(layerStyle.mapboxStyleURI) error=\(error)")
                    // Revert persisted selection so a bad style doesn't cause a crash loop on next launch
                    MapLayerStyle.apply(previousLayerStyle)
                    context.coordinator.currentLayerStyle = previousLayerStyle
                    return
                }
                context.coordinator.styleLoaded = true
                context.coordinator.setupSourcesAndLayers()
                context.coordinator.refreshData()
                if let pending = context.coordinator.pendingCamera {
                    context.coordinator.pendingCamera = nil
                    context.coordinator.applyCamera(pending)
                }
            }
            return
        }

        // Camera command
        if let cmd = cameraCommand, cmd.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = cmd.id
            context.coordinator.applyCamera(cmd)
        }

        if context.coordinator.styleLoaded {
            context.coordinator.refreshData()
        }
        context.coordinator.applyBrushMode(on: mapView, brush: eraseBrush)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var config: MapConfiguration
        var callbacks: MapCallbacks
        weak var mapView: MapboxMaps.MapView?
        var engineView: MapboxEngineView?
        var styleLoaded = false
        var currentLayerStyle: MapLayerStyle = .mapboxDark
        var lastCommandID: UUID?
        private var lastSegmentsSignature = ""
        private var lastAnnotationsSignature = ""
        private var lastCirclesSignature = ""
        private var viewAnnotations: [String: UIView] = [:]
        var isProgrammaticCamera = false
        var pendingCamera: MapCameraCommand? = nil
        /// Retains the camera-changed observation so it doesn't get cancelled immediately.
        var cameraChangedCancelable: AnyCancelable? = nil

        // Eraser brush state — mirrors MapKitEngine's coordinator.
        weak var brushPanRecognizer: UIPanGestureRecognizer?
        weak var mapTwoFingerPanRecognizer: UIPanGestureRecognizer?
        private var currentBrush: MapEraseBrush?
        private var brushIsBrushing = false
        private var brushLastSampleTime: CFTimeInterval = 0
        private var lastBrushSavedPanEnabled: Bool = true

        init(config: MapConfiguration, callbacks: MapCallbacks) {
            self.config = config
            self.callbacks = callbacks
        }

        // MARK: - Gestures

        private var gestureEndWorkItem: DispatchWorkItem?

        func scheduleGestureEnd() {
            gestureEndWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.callbacks.onGestureStateChanged?(false)
            }
            gestureEndWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
        }

        // MARK: - Camera

        func applyCamera(_ cmd: MapCameraCommand) {
            guard let mapView else { return }
            if !styleLoaded { pendingCamera = cmd }
            isProgrammaticCamera = true
            let resetDelay = cmd.animated ? 0.6 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + resetDelay) { [weak self] in
                self?.isProgrammaticCamera = false
            }
            switch cmd.kind {
            case let .setCamera(center, distance, heading, pitch):
                let zoom = Self.altitudeToZoom(distance, latitude: center.latitude)
                let cam = CameraOptions(center: center, zoom: zoom, bearing: heading, pitch: CGFloat(pitch))
                if cmd.animated { mapView.camera.ease(to: cam, duration: 0.5) } else { mapView.mapboxMap.setCamera(to: cam) }

            case let .setRegion(region):
                let sw = CLLocationCoordinate2D(
                    latitude: region.center.latitude - region.span.latitudeDelta / 2,
                    longitude: region.center.longitude - region.span.longitudeDelta / 2
                )
                let ne = CLLocationCoordinate2D(
                    latitude: region.center.latitude + region.span.latitudeDelta / 2,
                    longitude: region.center.longitude + region.span.longitudeDelta / 2
                )
                let bounds = CoordinateBounds(southwest: sw, northeast: ne)
                // v11: camera(for:) requires maxZoom and offset
                let cam = mapView.mapboxMap.camera(for: bounds, padding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), bearing: 0, pitch: 0, maxZoom: nil, offset: nil)
                if cmd.animated { mapView.camera.ease(to: cam, duration: 0.5) } else { mapView.mapboxMap.setCamera(to: cam) }

            case let .fitRect(mapRect, padding):
                let sw = MKMapPoint(x: mapRect.origin.x, y: mapRect.origin.y + mapRect.size.height).coordinate
                let ne = MKMapPoint(x: mapRect.origin.x + mapRect.size.width, y: mapRect.origin.y).coordinate
                let bounds = CoordinateBounds(southwest: sw, northeast: ne)
                let cam = mapView.mapboxMap.camera(for: bounds, padding: padding, bearing: 0, pitch: 0, maxZoom: nil, offset: nil)
                if cmd.animated { mapView.camera.ease(to: cam, duration: 0.5) } else { mapView.mapboxMap.setCamera(to: cam) }
            }
        }

        static func altitudeToZoom(_ altitude: CLLocationDistance, latitude: Double = 0) -> CGFloat {
            let C = 591657550.5 * cos(latitude * .pi / 180)
            return CGFloat(log2(C / max(1, altitude)))
        }

        static func zoomToAltitude(_ zoom: CGFloat, latitude: Double = 0) -> CLLocationDistance {
            let C = 591657550.5 * cos(latitude * .pi / 180)
            return C / pow(2, Double(zoom))
        }

        // MARK: - Sources & Layers

        func setupSourcesAndLayers() {
            guard let mapView, styleLoaded else { return }
            let mapboxMap: MapboxMap = mapView.mapboxMap

            lastSegmentsSignature = ""
            lastAnnotationsSignature = ""
            lastCirclesSignature = ""

            // Hide POI labels
            let poiLayers = ["poi-label"]
            for layerId in poiLayers {
                if mapboxMap.layerExists(withId: layerId) {
                    try? mapboxMap.setLayerProperty(for: layerId, property: "visibility", value: "none")
                }
            }

            guard let ev = engineView else { return }

            // Route source — v11: GeoJSONSource(id:), addSource without id param
            if !mapboxMap.sourceExists(withId: ev.routeSourceId) {
                var src = GeoJSONSource(id: ev.routeSourceId)
                src.data = .featureCollection(Turf.FeatureCollection(features: []))
                try? mapboxMap.addSource(src)
            }

            // Tail source
            if !mapboxMap.sourceExists(withId: ev.tailSourceId) {
                var src = GeoJSONSource(id: ev.tailSourceId)
                src.data = .featureCollection(Turf.FeatureCollection(features: []))
                try? mapboxMap.addSource(src)
            }

            // Circle source
            if !mapboxMap.sourceExists(withId: ev.circleSourceId) {
                var src = GeoJSONSource(id: ev.circleSourceId)
                src.data = .featureCollection(Turf.FeatureCollection(features: []))
                try? mapboxMap.addSource(src)
            }

            let isDark = currentLayerStyle.isDarkStyle
            let baseColor = currentLayerStyle.routeBaseColor
            let glowColor = currentLayerStyle.routeGlowColor

            addRouteLayers(mapboxMap: mapboxMap, baseColor: baseColor, glowColor: glowColor, isDark: isDark)
            addTailLayer(mapboxMap: mapboxMap, baseColor: baseColor, glowColor: glowColor, isDark: isDark)
            addCircleLayers(mapboxMap: mapboxMap, isDark: isDark)
            addBrushLayer(mapboxMap: mapboxMap)
        }

        private func addBrushLayer(mapboxMap: MapboxMap) {
            guard let ev = engineView else { return }
            if !mapboxMap.sourceExists(withId: ev.brushSourceId) {
                var src = GeoJSONSource(id: ev.brushSourceId)
                src.data = .featureCollection(Turf.FeatureCollection(features: []))
                try? mapboxMap.addSource(src)
            }
            if !mapboxMap.layerExists(withId: ev.brushLayerId) {
                var layer = CircleLayer(id: ev.brushLayerId, source: ev.brushSourceId)
                let accent = UIColor(red: 1.00, green: 0.45, blue: 0.05, alpha: 1.0)
                layer.circleColor = .constant(StyleColor(accent))
                layer.circleOpacity = .constant(0.32)
                layer.circleStrokeColor = .constant(StyleColor(accent))
                layer.circleStrokeOpacity = .constant(1.0)
                layer.circleStrokeWidth = .constant(2.5)
                // Radius gets driven from the brush config in updateBrushOverlay.
                layer.circleRadius = .constant(0)
                let anchor: LayerPosition = mapboxMap.layerExists(withId: ev.circleMainLayerId)
                    ? .above(ev.circleMainLayerId)
                    : (aboveBuildingsPosition(mapboxMap) ?? .default)
                try? mapboxMap.addLayer(layer, layerPosition: anchor)
            }
        }

        /// Find a layer position that places our overlays above 3D building
        /// extrusions. Mapbox styles render fill-extrusion layers above
        /// regular line layers, so without explicit positioning a route can
        /// disappear behind 3D buildings at street zoom. Falls back to the
        /// default top-of-stack position when no building layer is found.
        private func aboveBuildingsPosition(_ mapboxMap: MapboxMap) -> LayerPosition? {
            let candidates = [
                "building-extrusion",
                "3d-buildings",
                "building-3d",
                "building",
                "building-outline"
            ]
            for c in candidates where mapboxMap.layerExists(withId: c) {
                return .above(c)
            }
            return nil
        }

        // v11: helpers take MapboxMap directly (mapboxMap.style returns self)
        // Layers are chained: each one is positioned just above the previous
        // so the visual stack (bottom→top) ends up: building → glow → main →
        // highlight → dashed → tail → circle-glow → circle-main → brush.
        private func addRouteLayers(mapboxMap: MapboxMap, baseColor: UIColor, glowColor: UIColor, isDark: Bool) {
            guard let ev = engineView else { return }
            let buildingsAnchor = aboveBuildingsPosition(mapboxMap)

            if !mapboxMap.layerExists(withId: ev.routeGlowLayerId) {
                var glow = LineLayer(id: ev.routeGlowLayerId, source: ev.routeSourceId)
                glow.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                glow.lineColor = .constant(StyleColor(glowColor))
                glow.lineCap = .constant(.round)
                glow.lineJoin = .constant(.round)
                glow.lineOpacity = .constant(isDark ? 0.25 : 0.22)
                glow.lineWidth = .expression(Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    8;  5.0
                    12; 9.0
                    16; 14.0
                    20; 22.0
                })
                glow.lineBlur = .expression(Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    8;  2.0
                    14; 4.0
                    20; 6.0
                })
                try? mapboxMap.addLayer(glow, layerPosition: buildingsAnchor)
            }

            if !mapboxMap.layerExists(withId: ev.routeMainLayerId) {
                var main = LineLayer(id: ev.routeMainLayerId, source: ev.routeSourceId)
                main.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                main.lineColor = .constant(StyleColor(baseColor))
                main.lineCap = .constant(.round)
                main.lineJoin = .constant(.round)
                main.lineOpacity = .constant(1.0)
                main.lineWidth = .expression(Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    8;  2.0
                    12; 3.5
                    16; 5.0
                    20; 8.0
                })
                try? mapboxMap.addLayer(main, layerPosition: .above(ev.routeGlowLayerId))
            }

            if !mapboxMap.layerExists(withId: ev.routeHighlightLayerId) {
                var highlight = LineLayer(id: ev.routeHighlightLayerId, source: ev.routeSourceId)
                highlight.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                highlight.lineColor = .constant(StyleColor(UIColor.white))
                highlight.lineCap = .constant(.round)
                highlight.lineJoin = .constant(.round)
                highlight.lineOpacity = .constant(isDark ? 0.45 : 0.25)
                highlight.lineWidth = .expression(Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    8;  0.5
                    12; 0.9
                    16; 1.4
                    20; 2.0
                })
                try? mapboxMap.addLayer(highlight, layerPosition: .above(ev.routeMainLayerId))
            }

            // Dashed signal-loss segments render the main layer only. A glow layer would
            // scale its [10,10] dasharray by its own (larger) line width, putting solid
            // glow color inside the main layer's dash gaps.
            if !mapboxMap.layerExists(withId: ev.routeDashedMainLayerId) {
                var dmain = LineLayer(id: ev.routeDashedMainLayerId, source: ev.routeSourceId)
                dmain.filter = Exp(.eq) { Exp(.get) { "isGap" }; true }
                dmain.lineColor = .constant(StyleColor(baseColor))
                dmain.lineCap = .constant(.round)
                dmain.lineJoin = .constant(.round)
                dmain.lineOpacity = .constant(0.85)
                dmain.lineDasharray = .constant([10, 10])
                dmain.lineWidth = .expression(Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    8;  1.5
                    12; 2.6
                    16; 3.75
                    20; 6.0
                })
                try? mapboxMap.addLayer(dmain, layerPosition: .above(ev.routeHighlightLayerId))
            }
        }

        private func addTailLayer(mapboxMap: MapboxMap, baseColor: UIColor, glowColor: UIColor, isDark: Bool) {
            guard let ev = engineView else { return }
            if !mapboxMap.layerExists(withId: ev.tailLayerId) {
                var tail = LineLayer(id: ev.tailLayerId, source: ev.tailSourceId)
                tail.lineColor = .constant(StyleColor(baseColor))
                tail.lineCap = .constant(.round)
                tail.lineJoin = .constant(.round)
                tail.lineOpacity = .constant(0.90)
                tail.lineWidth = .expression(Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    8;  1.5
                    14; 2.5
                    20; 4.0
                })
                let anchor: LayerPosition = mapboxMap.layerExists(withId: ev.routeDashedMainLayerId)
                    ? .above(ev.routeDashedMainLayerId)
                    : (aboveBuildingsPosition(mapboxMap) ?? .default)
                try? mapboxMap.addLayer(tail, layerPosition: anchor)
            }
        }

        private func addCircleLayers(mapboxMap: MapboxMap, isDark: Bool) {
            guard let ev = engineView else { return }
            let green = UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)

            if !mapboxMap.layerExists(withId: ev.circleGlowLayerId) {
                var glow = CircleLayer(id: ev.circleGlowLayerId, source: ev.circleSourceId)
                glow.circleColor = .constant(StyleColor(green))
                glow.circleOpacity = .constant(isDark ? 0.50 : 0.35)
                glow.circleRadius = .constant(8)
                glow.circleBlur = .constant(0.8)
                let anchor: LayerPosition = mapboxMap.layerExists(withId: ev.tailLayerId)
                    ? .above(ev.tailLayerId)
                    : (mapboxMap.layerExists(withId: ev.routeDashedMainLayerId)
                        ? .above(ev.routeDashedMainLayerId)
                        : (aboveBuildingsPosition(mapboxMap) ?? .default))
                try? mapboxMap.addLayer(glow, layerPosition: anchor)
            }

            if !mapboxMap.layerExists(withId: ev.circleMainLayerId) {
                var main = CircleLayer(id: ev.circleMainLayerId, source: ev.circleSourceId)
                main.circleColor = .constant(StyleColor(green))
                main.circleOpacity = .constant(isDark ? 0.75 : 0.55)
                main.circleRadius = .constant(4)
                main.circleStrokeColor = .constant(StyleColor(green))
                main.circleStrokeWidth = .constant(1.5)
                main.circleStrokeOpacity = .constant(isDark ? 0.75 : 0.55)
                try? mapboxMap.addLayer(main, layerPosition: .above(ev.circleGlowLayerId))
            }
        }

        // MARK: - Data Refresh

        func refreshData() {
            guard let mapView, let ev = engineView, styleLoaded else { return }
            let mapboxMap: MapboxMap = mapView.mapboxMap

            let segSig = ev.segments.map { "\($0.id):\($0.isGap ? "d" : "s"):\($0.coordinates.count)" }.joined(separator: "|")
            if segSig != lastSegmentsSignature {
                lastSegmentsSignature = segSig
                let fc = buildRoutesFC(segments: ev.segments)
                guard mapboxMap.sourceExists(withId: ev.routeSourceId) else { return }
                mapboxMap.updateGeoJSONSource(withId: ev.routeSourceId, geoJSON: .featureCollection(fc))
            }

            if mapboxMap.sourceExists(withId: ev.tailSourceId) {
                if let liveTail = config.liveTail, liveTail.count == 2 {
                    var f = Turf.Feature(geometry: Turf.Geometry.lineString(Turf.LineString([liveTail[0], liveTail[1]])))
                    f.properties = [:]
                    let fc = Turf.FeatureCollection(features: [f])
                    mapboxMap.updateGeoJSONSource(withId: ev.tailSourceId, geoJSON: .featureCollection(fc))
                } else {
                    mapboxMap.updateGeoJSONSource(withId: ev.tailSourceId, geoJSON: .featureCollection(Turf.FeatureCollection(features: [])))
                }
            }

            let circleSig = ev.circles.map { "\(Int($0.center.latitude * 10000))_\(Int($0.center.longitude * 10000))" }.joined(separator: ",")
            if circleSig != lastCirclesSignature {
                lastCirclesSignature = circleSig
                let fc = buildCirclesFC(circles: ev.circles)
                guard mapboxMap.sourceExists(withId: ev.circleSourceId) else { return }
                mapboxMap.updateGeoJSONSource(withId: ev.circleSourceId, geoJSON: .featureCollection(fc))
            }

            let annSig = ev.annotations.map { ann -> String in
                var base = "\(ann.id):\(Int(ann.coordinate.latitude * 10000))_\(Int(ann.coordinate.longitude * 10000))"
                switch ann.kind {
                case let .memoryGroup(_, memories):
                    let memSig = memories.map { "\($0.id)|\($0.title)|\($0.notes)|\($0.imagePaths.count)|\($0.remoteImageURLs.count)" }.joined(separator: ";")
                    base += ":m:" + memSig
                case let .lifelogAvatar(showMood):
                    base += ":l:\(showMood)"
                case .robot:
                    break
                }
                return base
            }.joined(separator: "|")
            if annSig != lastAnnotationsSignature {
                lastAnnotationsSignature = annSig
                syncViewAnnotations(items: ev.annotations)
                if config.useZoomAwareVisibility { syncZoomAwareVisibility() }
            }
        }

        // MARK: - Zoom-Aware Visibility

        func syncZoomAwareVisibility() {
            guard let mapView else { return }
            let zoom = mapView.mapboxMap.cameraState.zoom
            let latDelta = 360.0 / pow(2.0, Double(zoom))
            let shouldShowPins = CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: latDelta)

            // Pin alpha works regardless of style state — it's a UIView property.
            let pinAlpha: CGFloat = shouldShowPins ? 1.0 : 0.0
            UIView.animate(withDuration: 0.2) {
                for (_, view) in self.viewAnnotations { view.alpha = pinAlpha }
            }

            // Dot layer visibility requires the Mapbox style to be loaded.
            // Skip this part if not ready; subsequent style-load completion or
            // camera-change events will retry.
            guard let ev = engineView, styleLoaded else { return }
            let dotVisibility = shouldShowPins ? "none" : "visible"
            let mapboxMap: MapboxMap = mapView.mapboxMap
            if mapboxMap.layerExists(withId: ev.circleGlowLayerId) {
                try? mapboxMap.setLayerProperty(for: ev.circleGlowLayerId, property: "visibility", value: dotVisibility)
            }
            if mapboxMap.layerExists(withId: ev.circleMainLayerId) {
                try? mapboxMap.setLayerProperty(for: ev.circleMainLayerId, property: "visibility", value: dotVisibility)
            }
        }

        private func buildRoutesFC(segments: [MapRouteSegment]) -> Turf.FeatureCollection {
            var feats: [Turf.Feature] = []
            for seg in segments where seg.coordinates.count >= 2 {
                var f = Turf.Feature(geometry: Turf.Geometry.lineString(Turf.LineString(seg.coordinates)))
                f.properties = [
                    "isGap": .init(booleanLiteral: seg.isGap),
                    "repeatWeight": .init(floatLiteral: seg.repeatWeight)
                ]
                feats.append(f)
            }
            return Turf.FeatureCollection(features: feats)
        }

        private func buildCirclesFC(circles: [MapCircleOverlay]) -> Turf.FeatureCollection {
            var feats: [Turf.Feature] = []
            for c in circles {
                var f = Turf.Feature(geometry: Turf.Geometry.point(Turf.Point(c.center)))
                f.properties = ["radius": .init(floatLiteral: c.radiusMeters)]
                feats.append(f)
            }
            return Turf.FeatureCollection(features: feats)
        }

        // MARK: - View Annotations

        private func syncViewAnnotations(items: [MapAnnotationItem]) {
            guard let mapView else { return }

            let newKeys = Set(items.map(\.id))
            for (key, view) in viewAnnotations where !newKeys.contains(key) {
                try? mapView.viewAnnotations.remove(view)
                viewAnnotations.removeValue(forKey: key)
            }

            for item in items {
                if let existingView = viewAnnotations[item.id] {
                    switch item.kind {
                    case .robot:
                        // Robot: position-only update, no mutable content
                        try? mapView.viewAnnotations.update(existingView, options: ViewAnnotationOptions(
                            geometry: Turf.Point(item.coordinate),
                            allowOverlap: true
                        ))
                        continue
                    case .memoryGroup, .lifelogAvatar:
                        // Content may have changed (memory text/photos, mood state) — rebuild
                        try? mapView.viewAnnotations.remove(existingView)
                        viewAnnotations.removeValue(forKey: item.id)
                        // fall through to creation below
                    }
                }

                let hostView: UIView
                switch item.kind {
                case let .memoryGroup(_, memories):
                    let pin = MemoryPin(cluster: memories)
                    let hosting = UIHostingController(rootView: pin)
                    hosting.view.backgroundColor = .clear
                    hosting.view.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
                    // Set initial alpha to match current zoom-aware state. Without this,
                    // a freshly-created hostView defaults to alpha=1.0 and only gets
                    // corrected when syncZoomAwareVisibility runs — which can be skipped
                    // (styleLoaded guard) or animate over 0.2s, leaving the pin visible at
                    // the wrong zoom and overlapping with the green dot layer.
                    if config.useZoomAwareVisibility {
                        let zoom = mapView.mapboxMap.cameraState.zoom
                        let latDelta = 360.0 / pow(2.0, Double(zoom))
                        let shouldShowPins = CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: latDelta)
                        hosting.view.alpha = CityDeepMemoryVisibility.pinAlpha(shouldShowPins: shouldShowPins)
                    }
                    hostView = hosting.view

                case .robot:
                    let robot = RobotMapMarkerView(
                        face: .front,
                        onOpenEquipment: { Task { @MainActor in AppFlowCoordinator.shared.requestModalPush(.equipment) } }
                    )
                    let hosting = UIHostingController(rootView: robot)
                    hosting.view.backgroundColor = .clear
                    hosting.view.frame = CGRect(x: 0, y: 0, width: Int(AvatarMapMarkerStyle.annotationSize), height: Int(AvatarMapMarkerStyle.annotationSize))
                    hostView = hosting.view

                case let .lifelogAvatar(showMood):
                    let moodHeight: CGFloat = showMood ? 38.0 : 0
                    let content = LifelogAvatarAnnotationContent(
                        shouldShowMoodQuestion: showMood,
                        onMoodTap: { [weak self] in self?.callbacks.onMoodTap?() },
                        onDoubleTap: { [weak self] in self?.callbacks.onAvatarDoubleTap?() }
                    )
                    let hosting = UIHostingController(rootView: content)
                    hosting.view.backgroundColor = .clear
                    let h = AvatarMapMarkerStyle.annotationSize + moodHeight
                    hosting.view.frame = CGRect(x: 0, y: 0, width: Int(AvatarMapMarkerStyle.annotationSize), height: Int(h))
                    hostView = hosting.view
                }

                let options = ViewAnnotationOptions(
                    geometry: Turf.Point(item.coordinate),
                    width: Double(hostView.frame.width),
                    height: Double(hostView.frame.height),
                    allowOverlap: true,
                    anchor: .bottom
                )

                try? mapView.viewAnnotations.add(hostView, options: options)

                if case let .memoryGroup(_, memories) = item.kind {
                    let tap = UITapGestureRecognizer()
                    let capturedMemories = memories
                    let capturedCallbacks = callbacks
                    tap.addTarget(MemoryTapHandler.shared, action: #selector(MemoryTapHandler.handleTap(_:)))
                    MemoryTapHandler.shared.register(tap, memories: capturedMemories, callbacks: capturedCallbacks)
                    hostView.addGestureRecognizer(tap)
                    hostView.isUserInteractionEnabled = true
                }

                viewAnnotations[item.id] = hostView
            }
        }

        // MARK: - Eraser brush

        func applyBrushMode(on mapView: MapboxMaps.MapView, brush: MapEraseBrush?) {
            let wasActive = currentBrush != nil
            let isActive = brush != nil
            currentBrush = brush

            // Only snapshot/restore on actual edge transitions. updateUIView
            // is called on every body render — re-saving while already active
            // would persist our own `false` as the "original" and leave the
            // map permanently un-pannable on exit.
            if !wasActive && isActive {
                lastBrushSavedPanEnabled = mapView.gestures.options.panEnabled
                mapView.gestures.options.panEnabled = false
            } else if wasActive && !isActive {
                mapView.gestures.options.panEnabled = lastBrushSavedPanEnabled
            }

            brushPanRecognizer?.isEnabled = isActive
            mapTwoFingerPanRecognizer?.isEnabled = isActive

            if let brush = brush, styleLoaded {
                if let layerId = engineView?.brushLayerId,
                   mapView.mapboxMap.layerExists(withId: layerId) {
                    try? mapView.mapboxMap.setLayerProperty(
                        for: layerId,
                        property: "circle-radius",
                        value: Double(brush.screenRadiusPoints)
                    )
                }
            }

            if !isActive {
                clearBrushOverlay(on: mapView)
                brushIsBrushing = false
            }
        }

        @objc func onBrushPan(_ gr: UIPanGestureRecognizer) {
            guard let brush = currentBrush else { return }
            guard let mapView else { return }

            switch gr.state {
            case .began:
                brushIsBrushing = true
                callbacks.onGestureStateChanged?(true)
                callbacks.onEraseBrushStrokeStart?()
                emitBrushSample(at: gr.location(in: mapView), on: mapView, brush: brush, force: true)
            case .changed:
                emitBrushSample(at: gr.location(in: mapView), on: mapView, brush: brush, force: false)
            case .ended, .cancelled, .failed:
                brushIsBrushing = false
                emitBrushSample(at: gr.location(in: mapView), on: mapView, brush: brush, force: true)
                callbacks.onEraseBrushStrokeEnd?()
                clearBrushOverlay(on: mapView)
                scheduleGestureEnd()
            default:
                break
            }
        }

        @objc func onMapTwoFingerPan(_ gr: UIPanGestureRecognizer) {
            guard currentBrush != nil else { return }
            guard let mapView else { return }

            switch gr.state {
            case .began, .changed:
                let translation = gr.translation(in: mapView)
                guard translation.x != 0 || translation.y != 0 else { return }
                gr.setTranslation(.zero, in: mapView)

                // Move the camera so the underlying map shifts opposite to
                // the finger drag direction (standard pan feel).
                let bounds = mapView.bounds.size
                guard bounds.width > 0, bounds.height > 0 else { return }
                let centerScreen = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
                let targetScreen = CGPoint(
                    x: centerScreen.x - translation.x,
                    y: centerScreen.y - translation.y
                )
                let newCenter = mapView.mapboxMap.coordinate(for: targetScreen)
                guard newCenter.latitude.isFinite, newCenter.longitude.isFinite else { return }
                isProgrammaticCamera = true
                mapView.mapboxMap.setCamera(to: CameraOptions(center: newCenter))
                // Reset the flag after this run loop tick. Without this, the
                // flag stays `true` forever and onCameraChanged ignores all
                // subsequent user gestures — breaking syncZoomAwareVisibility
                // (memory pin alpha / dot visibility) after a single brush-mode
                // two-finger pan.
                DispatchQueue.main.async { [weak self] in
                    self?.isProgrammaticCamera = false
                }
            default:
                break
            }
        }

        private func emitBrushSample(at screenPoint: CGPoint, on mapView: MapboxMaps.MapView, brush: MapEraseBrush, force: Bool) {
            let now = CACurrentMediaTime()
            if !force, now - brushLastSampleTime < 0.033 { return }
            brushLastSampleTime = now

            let coord = mapView.mapboxMap.coordinate(for: screenPoint)
            guard coord.latitude.isFinite, coord.longitude.isFinite else { return }

            // Convert fixed screen-radius into world meters via the projection
            // at the brush position so callers can hit-test in meter space.
            let edgePoint = CGPoint(x: screenPoint.x + brush.screenRadiusPoints, y: screenPoint.y)
            let edgeCoord = mapView.mapboxMap.coordinate(for: edgePoint)
            let centerLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let edgeLoc = CLLocation(latitude: edgeCoord.latitude, longitude: edgeCoord.longitude)
            let radiusMeters = max(1, centerLoc.distance(from: edgeLoc))

            updateBrushOverlay(on: mapView, center: coord)
            callbacks.onEraseBrushSwept?(coord, radiusMeters)
        }

        private func updateBrushOverlay(on mapView: MapboxMaps.MapView, center: CLLocationCoordinate2D) {
            guard styleLoaded, let sourceId = engineView?.brushSourceId else { return }
            guard mapView.mapboxMap.sourceExists(withId: sourceId) else { return }
            let feature = Turf.Feature(geometry: Turf.Geometry.point(Turf.Point(center)))
            let fc = Turf.FeatureCollection(features: [feature])
            mapView.mapboxMap.updateGeoJSONSource(withId: sourceId, geoJSON: .featureCollection(fc))
        }

        private func clearBrushOverlay(on mapView: MapboxMaps.MapView) {
            guard styleLoaded, let sourceId = engineView?.brushSourceId else { return }
            guard mapView.mapboxMap.sourceExists(withId: sourceId) else { return }
            mapView.mapboxMap.updateGeoJSONSource(withId: sourceId, geoJSON: .featureCollection(Turf.FeatureCollection(features: [])))
        }

        // Allow brush/two-finger pan to coexist with Mapbox's pinch.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// Helper class for tap handling in Mapbox view annotations
private final class MemoryTapHandler: NSObject {
    static let shared = MemoryTapHandler()

    private var handlers: [UITapGestureRecognizer: ([JourneyMemory], MapCallbacks)] = [:]

    func register(_ tap: UITapGestureRecognizer, memories: [JourneyMemory], callbacks: MapCallbacks) {
        handlers[tap] = (memories, callbacks)
    }

    @objc func handleTap(_ tap: UITapGestureRecognizer) {
        guard let (memories, callbacks) = handlers[tap] else { return }
        callbacks.onSelectMemories?(memories)
    }
}
