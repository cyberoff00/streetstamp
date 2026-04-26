import SwiftUI
import MapKit

// MARK: - MapKit-specific annotation types

final class UnifiedMemoryGroupAnnotation: NSObject, MKAnnotation {
    let key: String
    dynamic var coordinate: CLLocationCoordinate2D
    let items: [JourneyMemory]

    init(key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory]) {
        self.key = key
        self.coordinate = coordinate
        self.items = items
    }
}

final class UnifiedRobotAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

final class UnifiedLifelogAvatarAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var shouldShowMoodQuestion: Bool

    init(coordinate: CLLocationCoordinate2D, shouldShowMoodQuestion: Bool) {
        self.coordinate = coordinate
        self.shouldShowMoodQuestion = shouldShowMoodQuestion
    }
}

/// Small circle overlay marking a memory location
final class UnifiedMemoryDotCircle: MKCircle {}

/// The brush circle rendered while the user drags inside eraser mode. Lives
/// at the meter radius the engine computes from the brush's screen-point size
/// at the current map zoom.
final class UnifiedEraseBrushCircle: MKCircle {}

/// Pan recognizer that enters `.began` on touch-down rather than requiring
/// the standard ~10pt movement threshold. Eraser brush UX needs immediate
/// visual feedback the moment the finger lands.
///
/// Multi-touch (pinch zoom) cancels the brush so two-finger zoom doesn't
/// co-fire eraser samples. Without this, the first finger of a pinch
/// triggers `.began` and continues firing `.changed` events through the
/// zoom gesture.
final class ImmediatePanGestureRecognizer: UIPanGestureRecognizer {
    /// Window after touch-down before we commit to `.began`. If a second finger
    /// arrives within this window the gesture fails so pinch zoom takes over
    /// uncontested. ~60ms is long enough to catch a "near-simultaneous" second
    /// finger but short enough that single-finger erase still feels immediate.
    private static let multiTouchGuardSeconds: TimeInterval = 0.06

    private var pendingBeganWork: DispatchWorkItem?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // numberOfTouches reflects touches THIS recognizer is tracking — more
        // reliable than event.allTouches.
        if numberOfTouches > 1 {
            // Multi-touch already in flight (pinch). If we'd already begun,
            // transition through .cancelled so onBrushPan's cleanup runs;
            // .failed would silently skip the handler and leave brushOverlay
            // / stroke state hanging.
            pendingBeganWork?.cancel()
            state = (state == .began || state == .changed) ? .cancelled : .failed
            return
        }
        // Single finger — defer .began so a near-simultaneous second finger
        // can pre-empt us. Without this, `state = .began` fires synchronously
        // here, the brush's `case .began:` handler runs, and a stroke sample
        // is emitted before we ever get to see the second finger arrive for
        // a pinch zoom.
        guard state == .possible else { return }
        pendingBeganWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.numberOfTouches == 1, self.state == .possible else { return }
            self.state = .began
        }
        pendingBeganWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.multiTouchGuardSeconds, execute: work)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if numberOfTouches > 1 {
            pendingBeganWork?.cancel()
            if state == .began || state == .changed {
                state = .cancelled
            } else if state == .possible {
                state = .failed
            }
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        pendingBeganWork?.cancel()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        pendingBeganWork?.cancel()
    }

    override func reset() {
        super.reset()
        pendingBeganWork?.cancel()
        pendingBeganWork = nil
    }
}

// MARK: - MapKit Engine UIViewRepresentable

struct MapKitEngineView: UIViewRepresentable {
    let segments: [MapRouteSegment]
    let annotations: [MapAnnotationItem]
    let circles: [MapCircleOverlay]
    let eraseBrush: MapEraseBrush?
    let cameraCommand: MapCameraCommand?
    let config: MapConfiguration
    let callbacks: MapCallbacks
    let layerStyle: MapLayerStyle

    func makeCoordinator() -> Coordinator { Coordinator(config: config, callbacks: callbacks, layerStyle: layerStyle) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsTraffic = false
        map.pointOfInterestFilter = .excludingAll

        applyAppearance(on: map)

        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "robot")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "memoryGroup")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "lifelogAvatar")

        if config.isInteractive {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onUserGesture(_:)))
            pan.cancelsTouchesInView = false
            map.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onUserGesture(_:)))
            pinch.cancelsTouchesInView = false
            map.addGestureRecognizer(pinch)

            // Eraser brush pan — fires on touch-down so the brush circle
            // appears immediately and a single tap can also erase. While brush
            // mode is active we disable map scroll entirely; the two-finger
            // pan below restores manual map panning. Pinch-to-zoom is a
            // separate recognizer and keeps working.
            let brushPan = ImmediatePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onBrushPan(_:)))
            brushPan.maximumNumberOfTouches = 1
            brushPan.cancelsTouchesInView = false
            brushPan.delegate = context.coordinator
            map.addGestureRecognizer(brushPan)
            context.coordinator.brushPanRecognizer = brushPan

            // Manual two-finger pan, only enabled in brush mode. We can't
            // rely on tweaking MKMapView's internal pan recognizer because
            // it lives on a private subview, not the map view itself.
            let twoPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onMapTwoFingerPan(_:)))
            twoPan.minimumNumberOfTouches = 2
            twoPan.maximumNumberOfTouches = 2
            twoPan.cancelsTouchesInView = false
            twoPan.delegate = context.coordinator
            twoPan.isEnabled = false
            map.addGestureRecognizer(twoPan)
            context.coordinator.mapTwoFingerPanRecognizer = twoPan
        }

        // Apply initial camera + data
        if let cmd = cameraCommand {
            context.coordinator.lastCommandID = cmd.id
            context.coordinator.applyCamera(cmd, to: map)
        }
        context.coordinator.applyBrushMode(on: map, brush: eraseBrush)
        context.coordinator.syncAll(on: map, segments: segments, annotations: annotations, circles: circles)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.config = config
        context.coordinator.callbacks = callbacks
        context.coordinator.layerStyle = layerStyle
        applyAppearance(on: map)

        // Camera command
        if let cmd = cameraCommand, cmd.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = cmd.id
            context.coordinator.applyCamera(cmd, to: map)
        }

        context.coordinator.applyBrushMode(on: map, brush: eraseBrush)
        context.coordinator.syncAll(on: map, segments: segments, annotations: annotations, circles: circles)

        // Sync altitude back to caller
        let alt = map.camera.altitude
        callbacks.onCameraAltitudeChanged?(alt)
    }

    private func applyAppearance(on map: MKMapView) {
        map.overrideUserInterfaceStyle = layerStyle.mapKitInterfaceStyle
        map.mapType = layerStyle.mapKitType
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var config: MapConfiguration
        var callbacks: MapCallbacks
        var layerStyle: MapLayerStyle
        var lastCommandID: UUID?

        // Annotation state
        private var robotAnnotation: UnifiedRobotAnnotation?
        private var memoryAnnotationsByKey: [String: UnifiedMemoryGroupAnnotation] = [:]
        private var memoryHostingsByKey: [String: UIHostingController<MemoryPin>] = [:]
        private var lifelogAvatarAnnotation: UnifiedLifelogAvatarAnnotation?

        // Overlay state
        private var lastSegmentsSignature: String = ""
        private var lastCirclesSignature: String = ""
        private var lastAppearance: String?
        private var lastAltitudeBucket: Int?
        private var renderedSegments: [MapRouteSegment] = []
        private var routeOverlays: [StyledPolyline] = []
        private var tailOverlay: MKPolyline?

        // Eraser brush state
        weak var brushPanRecognizer: UIPanGestureRecognizer?
        weak var mapTwoFingerPanRecognizer: UIPanGestureRecognizer?
        private var currentBrush: MapEraseBrush?
        private var brushOverlay: UnifiedEraseBrushCircle?
        private var brushIsBrushing: Bool = false
        private var brushLastSampleTime: CFTimeInterval = 0

        // Gesture
        private var isProgrammaticRegionChange = false

        init(config: MapConfiguration, callbacks: MapCallbacks, layerStyle: MapLayerStyle = .mutedDark) {
            self.config = config
            self.callbacks = callbacks
            self.layerStyle = layerStyle
        }

        // MARK: - Sync all

        func syncAll(on map: MKMapView, segments: [MapRouteSegment], annotations: [MapAnnotationItem], circles: [MapCircleOverlay]) {
            syncOverlays(on: map, segments: segments)
            syncTail(on: map)
            syncCircles(on: map, circles: circles)
            syncAnnotations(on: map, items: annotations)
        }

        // MARK: - Camera

        func applyCamera(_ cmd: MapCameraCommand, to map: MKMapView) {
            isProgrammaticRegionChange = true
            switch cmd.kind {
            case let .setCamera(center, distance, heading, pitch):
                let cam = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: pitch, heading: heading)
                map.setCamera(cam, animated: cmd.animated)
            case let .setRegion(region):
                map.setRegion(region, animated: cmd.animated)
            case let .fitRect(rect, padding):
                map.setVisibleMapRect(rect, edgePadding: padding, animated: cmd.animated)
            }
        }

        // MARK: - Gestures

        @objc func onUserGesture(_ gr: UIGestureRecognizer) {
            if gr.state == .began || gr.state == .changed {
                callbacks.onFollowUserChanged?(false)
                callbacks.onGestureStateChanged?(true)
            } else if gr.state == .ended || gr.state == .cancelled || gr.state == .failed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.callbacks.onGestureStateChanged?(false)
                }
            }
        }

        // MARK: - Eraser brush

        /// Apply or clear brush mode. While active, the map's built-in scroll
        /// is disabled so single-finger drags reach the brush; our own
        /// two-finger pan recognizer takes over map panning. Pinch-zoom is
        /// a separate gesture and keeps working.
        ///
        /// Only writes side effects on actual edge transitions — updateUIView
        /// fires on every body render and we don't want to repeatedly poke
        /// gesture/scroll state mid-stroke.
        func applyBrushMode(on map: MKMapView, brush: MapEraseBrush?) {
            let wasActive = currentBrush != nil
            let isActive = brush != nil
            currentBrush = brush

            if !wasActive && isActive {
                map.isScrollEnabled = false
                brushPanRecognizer?.isEnabled = true
                mapTwoFingerPanRecognizer?.isEnabled = true
            } else if wasActive && !isActive {
                map.isScrollEnabled = true
                brushPanRecognizer?.isEnabled = false
                mapTwoFingerPanRecognizer?.isEnabled = false
                removeBrushOverlay(on: map)
                brushIsBrushing = false
            }
        }

        @objc func onMapTwoFingerPan(_ gr: UIPanGestureRecognizer) {
            guard currentBrush != nil else { return }
            guard let map = gr.view as? MKMapView else { return }

            // Defer to pinch zoom while it's active. MKMapView's built-in
            // pinch drives camera zoom; if we also call setCenter() on every
            // translation tick the two writes race and pinch only advances a
            // sliver per gesture before our setCenter() snaps the region back.
            // We detect pinch via the parallel UIPinchGestureRecognizer
            // installed in makeUIView (it doesn't drive zoom itself; its
            // state just mirrors that of the built-in pinch).
            if let recognizers = map.gestureRecognizers {
                for r in recognizers where r is UIPinchGestureRecognizer {
                    if r.state == .began || r.state == .changed {
                        if gr.state == .began || gr.state == .changed {
                            gr.state = .cancelled
                        }
                        return
                    }
                }
            }

            switch gr.state {
            case .began, .changed:
                let translation = gr.translation(in: map)
                guard translation.x != 0 || translation.y != 0 else { return }
                gr.setTranslation(.zero, in: map)

                let bounds = map.bounds.size
                guard bounds.width > 0, bounds.height > 0 else { return }
                let span = map.region.span
                let lonDelta = -Double(translation.x) * span.longitudeDelta / Double(bounds.width)
                let latDelta = Double(translation.y) * span.latitudeDelta / Double(bounds.height)
                var center = map.region.center
                center.latitude = max(-85, min(85, center.latitude + latDelta))
                center.longitude += lonDelta
                isProgrammaticRegionChange = true
                map.setCenter(center, animated: false)
            default:
                break
            }
        }

        @objc func onBrushPan(_ gr: UIPanGestureRecognizer) {
            guard let brush = currentBrush else { return }
            guard let map = gr.view as? MKMapView else { return }

            switch gr.state {
            case .began:
                brushIsBrushing = true
                callbacks.onGestureStateChanged?(true)
                callbacks.onEraseBrushStrokeStart?()
                emitBrushSample(at: gr.location(in: map), on: map, brush: brush, force: true)
            case .changed:
                emitBrushSample(at: gr.location(in: map), on: map, brush: brush, force: false)
            case .ended, .cancelled, .failed:
                brushIsBrushing = false
                emitBrushSample(at: gr.location(in: map), on: map, brush: brush, force: true)
                callbacks.onEraseBrushStrokeEnd?()
                removeBrushOverlay(on: map)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.callbacks.onGestureStateChanged?(false)
                }
            default:
                break
            }
        }

        private func emitBrushSample(at screenPoint: CGPoint, on map: MKMapView, brush: MapEraseBrush, force: Bool) {
            // Throttle to ~33ms (≈30 Hz). Pan gesture events fire at display
            // frequency; we don't need to compute mask updates that fast.
            let now = CACurrentMediaTime()
            if !force, now - brushLastSampleTime < 0.033 { return }
            brushLastSampleTime = now

            let coord = map.convert(screenPoint, toCoordinateFrom: map)
            // Convert the brush's fixed screen-point size into world meters
            // using the current map projection at the brush position. This
            // keeps the brush a constant visual size as the user zooms.
            let edgePoint = CGPoint(x: screenPoint.x + brush.screenRadiusPoints, y: screenPoint.y)
            let edgeCoord = map.convert(edgePoint, toCoordinateFrom: map)
            let centerLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let edgeLoc = CLLocation(latitude: edgeCoord.latitude, longitude: edgeCoord.longitude)
            let radiusMeters = max(1, centerLoc.distance(from: edgeLoc))

            updateBrushOverlay(on: map, center: coord, radius: radiusMeters)
            callbacks.onEraseBrushSwept?(coord, radiusMeters)
        }

        private func updateBrushOverlay(on map: MKMapView, center: CLLocationCoordinate2D, radius: CLLocationDistance) {
            removeBrushOverlay(on: map)
            let circle = UnifiedEraseBrushCircle(center: center, radius: radius)
            // .aboveLabels keeps the brush visible above polylines and labels —
            // critical for the user to see where the eraser is hovering.
            map.addOverlay(circle, level: .aboveLabels)
            brushOverlay = circle
        }

        private func removeBrushOverlay(on map: MKMapView) {
            if let old = brushOverlay {
                map.removeOverlay(old)
                brushOverlay = nil
            }
        }

        // The brush pan recognizer must coexist with the map's pinch gesture
        // (so users can still zoom in/out mid-edit). Single-finger pan is
        // already disabled via map.isScrollEnabled = false during brush mode.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: - Overlays

        private func segmentsSignature(_ segments: [MapRouteSegment]) -> String {
            segments.map { "\($0.id):\($0.isGap ? "d" : "s"):\($0.coordinates.count)" }.joined(separator: "|")
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
                "\(Int((c.latitude * 2_000).rounded())):\(Int((c.longitude * 2_000).rounded()))"
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

        func syncOverlays(on map: MKMapView, segments: [MapRouteSegment]) {
            let currentAppearance = layerStyle.rawValue
            if currentAppearance != lastAppearance {
                lastAppearance = currentAppearance
                if lastSegmentsSignature != "" {
                    refreshOverlayStyles(on: map, segments: segments)
                    return
                }
            }

            if config.useAltitudeDependentWidths {
                lastAltitudeBucket = MapViewRouteRenderStyle.altitudeBucket(for: map.camera.altitude)
            }

            let segSig = segmentsSignature(segments)
            guard segSig != lastSegmentsSignature else { return }

            // Compute repeat weights
            var counts: [String: Int] = [:]
            for seg in segments where !seg.isGap && seg.coordinates.count >= 2 {
                let sig = segmentSignature(seg.coordinates)
                counts[sig, default: 0] += 1
            }
            let p95 = max(1.0, quantile(Array(counts.values), p: 0.95))

            if config.useAltitudeDependentWidths {
                // Prefix-matching optimization for live tracking
                let commonPrefixCount = sharedPrefixCount(lhs: renderedSegments, rhs: segments)

                if commonPrefixCount < routeOverlays.count {
                    let stale = Array(routeOverlays[commonPrefixCount...])
                    map.removeOverlays(stale)
                    routeOverlays.removeSubrange(commonPrefixCount..<routeOverlays.count)
                }

                if commonPrefixCount < segments.count {
                    var appended: [StyledPolyline] = []
                    appended.reserveCapacity(segments.count - commonPrefixCount)
                    for seg in segments[commonPrefixCount...] where seg.coordinates.count > 1 {
                        let poly = StyledPolyline(coordinates: seg.coordinates, count: seg.coordinates.count)
                        poly.isGap = seg.isGap
                        if !poly.isGap {
                            // Trust upstream weight when present (caller already deduped/weighted);
                            // otherwise compute from counts collected here.
                            if seg.repeatWeight > 0 {
                                poly.repeatWeight = max(0, min(1, seg.repeatWeight))
                            } else if let n = counts[segmentSignature(seg.coordinates)] {
                                poly.repeatWeight = min(1.0, log(1.0 + Double(n)) / log(1.0 + p95))
                            }
                        }
                        poly.title = poly.isGap ? "route_dashed" : "route_solid"
                        appended.append(poly)
                    }
                    if !appended.isEmpty {
                        map.addOverlays(appended)
                        routeOverlays.append(contentsOf: appended)
                    }
                }

                // Keep tail above newly-added route overlays
                if let tail = tailOverlay {
                    map.removeOverlay(tail)
                    map.addOverlay(tail)
                }
            } else {
                // Simple full rebuild for static maps
                map.removeOverlays(routeOverlays)
                routeOverlays.removeAll()

                for seg in segments where seg.coordinates.count >= 2 {
                    let poly = StyledPolyline(coordinates: seg.coordinates, count: seg.coordinates.count)
                    poly.isGap = seg.isGap
                    if seg.repeatWeight > 0 {
                        // Trust upstream weight when present (caller already deduped/weighted).
                        poly.repeatWeight = max(0, min(1, seg.repeatWeight))
                    } else if let n = counts[segmentSignature(seg.coordinates)], !poly.isGap {
                        poly.repeatWeight = min(1.0, log(1.0 + Double(n)) / log(1.0 + p95))
                    } else {
                        poly.repeatWeight = max(0, min(1, seg.repeatWeight))
                    }
                    map.addOverlay(poly)
                    routeOverlays.append(poly)
                }
            }

            renderedSegments = segments
            lastSegmentsSignature = segSig
        }

        private func syncTail(on map: MKMapView) {
            guard let liveTail = config.liveTail else {
                if let old = tailOverlay {
                    map.removeOverlay(old)
                    tailOverlay = nil
                }
                return
            }

            let tailSig = liveTail.map { "\(Int($0.latitude*1e5)):\(Int($0.longitude*1e5))" }.joined(separator: "|")
            let oldSig = tailOverlay.map { _ in "exists" } ?? ""
            if tailSig == oldSig { return }

            if let old = tailOverlay {
                map.removeOverlay(old)
                tailOverlay = nil
            }
            if liveTail.count == 2 {
                let poly = MKPolyline(coordinates: liveTail, count: liveTail.count)
                poly.title = "tail"
                map.addOverlay(poly)
                tailOverlay = poly
            }
        }

        private func syncCircles(on map: MKMapView, circles: [MapCircleOverlay]) {
            let sig = circles.map { "\(Int($0.center.latitude * 10000))_\(Int($0.center.longitude * 10000))" }.joined(separator: ",")
            guard sig != lastCirclesSignature else { return }
            lastCirclesSignature = sig

            // Remove old memory dot circles
            let oldDots = map.overlays.filter { $0 is UnifiedMemoryDotCircle }
            map.removeOverlays(oldDots)

            for circle in circles {
                let mkCircle = UnifiedMemoryDotCircle(center: circle.center, radius: circle.radiusMeters)
                map.addOverlay(mkCircle, level: .aboveRoads)
            }
        }

        private func refreshOverlayStyles(on map: MKMapView, segments: [MapRouteSegment]) {
            lastSegmentsSignature = ""
            renderedSegments = []
            map.removeOverlays(routeOverlays)
            routeOverlays.removeAll()
            syncOverlays(on: map, segments: segments)
        }

        private func sharedPrefixCount(lhs: [MapRouteSegment], rhs: [MapRouteSegment]) -> Int {
            let limit = min(lhs.count, rhs.count)
            var index = 0
            while index < limit {
                if lhs[index] != rhs[index] { break }
                index += 1
            }
            return index
        }

        // MARK: - Annotations

        func syncAnnotations(on map: MKMapView, items: [MapAnnotationItem]) {
            var memoryKeys: Set<String> = []
            var hasRobot = false
            var hasLifelogAvatar = false

            for item in items {
                switch item.kind {
                case let .memoryGroup(key, memories):
                    memoryKeys.insert(key)
                    syncMemoryAnnotation(on: map, key: key, coordinate: item.coordinate, items: memories)

                case .robot:
                    hasRobot = true
                    syncRobotAnnotation(on: map, coordinate: item.coordinate)

                case let .lifelogAvatar(showMood):
                    hasLifelogAvatar = true
                    syncLifelogAvatarAnnotation(on: map, coordinate: item.coordinate, showMood: showMood)
                }
            }

            // Remove stale memory annotations
            for key in Set(memoryAnnotationsByKey.keys).subtracting(memoryKeys) {
                if let ann = memoryAnnotationsByKey.removeValue(forKey: key) {
                    map.removeAnnotation(ann)
                }
                memoryHostingsByKey.removeValue(forKey: key)
            }

            // Remove robot if not present
            if !hasRobot, let ann = robotAnnotation {
                map.removeAnnotation(ann)
                robotAnnotation = nil
            }

            // Remove lifelog avatar if not present
            if !hasLifelogAvatar, let ann = lifelogAvatarAnnotation {
                map.removeAnnotation(ann)
                lifelogAvatarAnnotation = nil
            }
        }

        private func syncRobotAnnotation(on map: MKMapView, coordinate: CLLocationCoordinate2D) {
            if let existing = robotAnnotation {
                existing.coordinate = coordinate
            } else {
                let ann = UnifiedRobotAnnotation(coordinate: coordinate)
                robotAnnotation = ann
                map.addAnnotation(ann)
            }
        }

        private func syncMemoryAnnotation(on map: MKMapView, key: String, coordinate: CLLocationCoordinate2D, items: [JourneyMemory]) {
            func itemsSignature(_ items: [JourneyMemory]) -> String {
                items.sorted { $0.id < $1.id }
                    .map { "\($0.id)|t:\($0.title)|n:\($0.notes)|p:\($0.imagePaths.joined())|rp:\($0.remoteImageURLs.joined())" }
                    .joined(separator: ";")
            }

            if let ann = memoryAnnotationsByKey[key] {
                ann.coordinate = coordinate
                if ann.items.count != items.count || itemsSignature(ann.items) != itemsSignature(items) {
                    map.removeAnnotation(ann)
                    memoryHostingsByKey.removeValue(forKey: key)
                    let newAnn = UnifiedMemoryGroupAnnotation(key: key, coordinate: coordinate, items: items)
                    memoryAnnotationsByKey[key] = newAnn
                    map.addAnnotation(newAnn)
                }
            } else {
                let ann = UnifiedMemoryGroupAnnotation(key: key, coordinate: coordinate, items: items)
                memoryAnnotationsByKey[key] = ann
                map.addAnnotation(ann)
            }
        }

        private func syncLifelogAvatarAnnotation(on map: MKMapView, coordinate: CLLocationCoordinate2D, showMood: Bool) {
            if let ann = lifelogAvatarAnnotation {
                ann.coordinate = coordinate
                if ann.shouldShowMoodQuestion != showMood {
                    ann.shouldShowMoodQuestion = showMood
                    map.removeAnnotation(ann)
                    map.addAnnotation(ann)
                }
            } else {
                let ann = UnifiedLifelogAvatarAnnotation(coordinate: coordinate, shouldShowMoodQuestion: showMood)
                lifelogAvatarAnnotation = ann
                map.addAnnotation(ann)
            }
        }

        private func refreshMemoryPinModes(on map: MKMapView) {
            guard let threshold = config.memoryCompactAltitude else { return }
            let isCompact = map.camera.altitude >= threshold
            for (key, hosting) in memoryHostingsByKey {
                guard let ann = memoryAnnotationsByKey[key] else { continue }
                hosting.rootView = MemoryPin(cluster: ann.items, isCompact: isCompact)
            }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Eraser brush: bright orange disc following the user's finger.
            // High contrast + thick stroke so it's unmistakably visible
            // against any underlying map style.
            if let brush = overlay as? UnifiedEraseBrushCircle {
                let r = MKCircleRenderer(circle: brush)
                let accent = UIColor(red: 1.00, green: 0.45, blue: 0.05, alpha: 1.0)
                r.fillColor = accent.withAlphaComponent(0.32)
                r.strokeColor = accent
                r.lineWidth = 2.5
                return r
            }

            // Memory dot circle
            if let dot = overlay as? UnifiedMemoryDotCircle {
                let r = MKCircleRenderer(circle: dot)
                let isDark = layerStyle.isDarkStyle
                let green = UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)
                r.fillColor = green.withAlphaComponent(isDark ? 0.50 : 0.35)
                r.strokeColor = green.withAlphaComponent(isDark ? 0.75 : 0.55)
                r.lineWidth = 1.5
                if config.useZoomAwareVisibility {
                    let shouldShowPins = CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: mapView.region.span.latitudeDelta)
                    r.alpha = CityDeepMemoryVisibility.dotAlpha(shouldShowPins: shouldShowPins)
                }
                return r
            }

            guard let poly = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let isDark = layerStyle.isDarkStyle
            let base = layerStyle.routeBaseColor
            let glowTint = layerStyle.routeGlowColor

            // Tail overlay (live tracking)
            if poly.title == "tail" {
                return renderTail(poly: poly, isDark: isDark, base: base, glowTint: glowTint, altitude: mapView.camera.altitude)
            }

            // Route overlay
            guard let styled = poly as? StyledPolyline else {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.lineWidth = 2.2
                renderer.lineCap = .round
                renderer.lineJoin = .round
                renderer.strokeColor = base.withAlphaComponent(0.94)
                return renderer
            }

            return renderRoute(styled: styled, isDark: isDark, base: base, glowTint: glowTint, altitude: mapView.camera.altitude)
        }

        private func renderTail(poly: MKPolyline, isDark: Bool, base: UIColor, glowTint: UIColor, altitude: CLLocationDistance) -> MKOverlayRenderer {
            let tailMain = MKPolylineRenderer(polyline: poly)
            let width: CGFloat
            if config.useAltitudeDependentWidths, let mode = config.travelMode {
                width = max(2.0, min(3.1, MapViewRouteRenderStyle.coreWidth(forAltitude: altitude, mode: mode) * 0.82))
            } else {
                width = 2.2
            }
            tailMain.strokeColor = base.withAlphaComponent(0.90)
            tailMain.lineWidth = width
            tailMain.lineCap = .round
            tailMain.lineJoin = .round

            if isDark {
                let tailGlow = MKPolylineRenderer(polyline: poly)
                tailGlow.lineWidth = width * 2.5
                tailGlow.lineCap = .round
                tailGlow.lineJoin = .round
                tailGlow.strokeColor = glowTint.withAlphaComponent(0.18)
                let mr = LayeredPolylineRenderer(renderers: [tailGlow, tailMain])
                mr.glowBlur = 6.0
                mr.glowColor = glowTint.withAlphaComponent(0.45).cgColor
                return mr
            }
            return tailMain
        }

        private func renderRoute(styled: StyledPolyline, isDark: Bool, base: UIColor, glowTint: UIColor, altitude: CLLocationDistance) -> MKOverlayRenderer {
            let isGap = styled.isGap
            let weight = CGFloat(max(0, min(1, styled.repeatWeight)))
            let gapDash = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }

            let mainWidth: CGFloat
            let glowWidth: CGFloat
            let highlightWidth: CGFloat

            if config.useAltitudeDependentWidths, let mode = config.travelMode {
                let widths = MapViewRouteRenderStyle.layerWidths(forAltitude: altitude, mode: mode, repeatWeight: weight, isGap: isGap)
                mainWidth = widths.main
                glowWidth = widths.glow
                highlightWidth = widths.highlight
            } else {
                // Static widths for city/detail/lifelog views
                if isGap {
                    mainWidth = config.travelMode == nil && config.liveTail == nil && !config.useAltitudeDependentWidths
                        ? (config.useZoomAwareVisibility ? 1.65 : 1.65) // CityDeep and JourneyDetail (solid base 2.2 × 0.75)
                        : 2.1 // Lifelog (solid base 2.8 × 0.75)
                    glowWidth = mainWidth * 2.2
                    highlightWidth = 0
                } else {
                    mainWidth = 2.2 + weight * 0.8
                    glowWidth = mainWidth * 2.5
                    highlightWidth = mainWidth * 0.35
                }
            }

            let glowAlpha: CGFloat = isDark ? 0.25 : 0.12
            let mainAlpha: CGFloat = isGap ? 0.85 : 1.0

            // Main layer (dashed for gap segments)
            let mainLayer = MKPolylineRenderer(polyline: styled)
            mainLayer.lineWidth = mainWidth
            mainLayer.lineCap = .round
            mainLayer.lineJoin = .round
            mainLayer.strokeColor = base.withAlphaComponent(mainAlpha)
            if isGap { mainLayer.lineDashPattern = gapDash }

            // Dashed signal-loss segments render the main layer only. Glow + shadow
            // diffuse color into the dash gaps and make the "gap" look continuous.
            if isGap {
                return LayeredPolylineRenderer(renderers: [mainLayer])
            }

            // Glow layer
            let glowLayer = MKPolylineRenderer(polyline: styled)
            glowLayer.lineWidth = glowWidth
            glowLayer.lineCap = .round
            glowLayer.lineJoin = .round
            glowLayer.strokeColor = glowTint.withAlphaComponent(glowAlpha)

            // Highlight layer
            let highlightLayer = MKPolylineRenderer(polyline: styled)
            highlightLayer.lineWidth = highlightWidth
            highlightLayer.lineCap = .round
            highlightLayer.lineJoin = .round
            highlightLayer.strokeColor = UIColor.white.withAlphaComponent(isDark ? 0.45 : 0.25)

            let lr = LayeredPolylineRenderer(renderers: [glowLayer, mainLayer, highlightLayer])
            if isDark {
                lr.glowBlur = config.useAltitudeDependentWidths ? 8.0 : 6.0
                lr.glowColor = glowTint.withAlphaComponent(0.50).cgColor
            }
            return lr
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let ann = annotation as? UnifiedRobotAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "robot", for: ann)
                configureRobotView(view)
                return view
            }

            if let ann = annotation as? UnifiedMemoryGroupAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "memoryGroup", for: ann)
                configureMemoryGroupView(view, annotation: ann, mapView: mapView)
                return view
            }

            if let ann = annotation as? UnifiedLifelogAvatarAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "lifelogAvatar")
                    ?? MKAnnotationView(annotation: ann, reuseIdentifier: "lifelogAvatar")
                configureLifelogAvatarView(view, annotation: ann)
                return view
            }

            return nil
        }

        private func configureRobotView(_ view: MKAnnotationView) {
            view.canShowCallout = false
            view.bounds = CGRect(x: 0, y: 0, width: AvatarMapMarkerStyle.annotationSize, height: AvatarMapMarkerStyle.annotationSize)
            view.backgroundColor = .clear
            view.centerOffset = .zero
            view.displayPriority = .required
            view.collisionMode = .circle
            if #available(iOS 14.0, *) { view.zPriority = .min }

            let hosting = UIHostingController(
                rootView: RobotMapMarkerView(
                    face: .front,
                    onOpenEquipment: {
                        Task { @MainActor in AppFlowCoordinator.shared.requestModalPush(.equipment) }
                    }
                )
            )
            hosting.view.backgroundColor = .clear
            hosting.view.frame = view.bounds
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)
        }

        private func configureMemoryGroupView(_ view: MKAnnotationView, annotation: UnifiedMemoryGroupAnnotation, mapView: MKMapView) {
            view.canShowCallout = false
            view.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
            view.backgroundColor = .clear
            view.displayPriority = .required
            if #available(iOS 14.0, *) { view.zPriority = .max }

            let isCompact: Bool
            if let threshold = config.memoryCompactAltitude {
                isCompact = mapView.camera.altitude >= threshold
            } else {
                isCompact = false
            }

            let hosting = UIHostingController(rootView: MemoryPin(cluster: annotation.items, isCompact: isCompact))
            hosting.view.backgroundColor = .clear
            hosting.view.frame = view.bounds
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)
            memoryHostingsByKey[annotation.key] = hosting

            if config.useZoomAwareVisibility {
                let shouldShowPins = CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: mapView.region.span.latitudeDelta)
                view.alpha = CityDeepMemoryVisibility.pinAlpha(shouldShowPins: shouldShowPins)
            }
        }

        private func configureLifelogAvatarView(_ view: MKAnnotationView, annotation: UnifiedLifelogAvatarAnnotation) {
            view.annotation = annotation
            view.canShowCallout = false
            view.backgroundColor = .clear

            let moodRowHeight: CGFloat = annotation.shouldShowMoodQuestion ? 38.0 : 0
            let size = CGSize(
                width: AvatarMapMarkerStyle.annotationSize,
                height: AvatarMapMarkerStyle.annotationSize + moodRowHeight
            )
            view.frame = CGRect(origin: .zero, size: size)
            view.centerOffset = CGPoint(x: 0, y: -size.height / 2)

            let content = LifelogAvatarAnnotationContent(
                shouldShowMoodQuestion: annotation.shouldShowMoodQuestion,
                onMoodTap: { [weak self] in self?.callbacks.onMoodTap?() },
                onDoubleTap: { [weak self] in self?.callbacks.onAvatarDoubleTap?() }
            )
            let hosting = UIHostingController(rootView: content)
            hosting.view.backgroundColor = .clear
            hosting.view.frame = CGRect(origin: .zero, size: size)
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let ann = view.annotation as? UnifiedRobotAnnotation {
                mapView.deselectAnnotation(ann, animated: false)
                return
            }

            if let ann = view.annotation as? UnifiedMemoryGroupAnnotation {
                callbacks.onSelectMemories?(ann.items)
                mapView.deselectAnnotation(ann, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isProgrammaticRegionChange {
                callbacks.onFollowUserChanged?(false)
                callbacks.onGestureStateChanged?(true)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange { isProgrammaticRegionChange = false }

            if config.useAltitudeDependentWidths {
                let currentBucket = MapViewRouteRenderStyle.altitudeBucket(for: mapView.camera.altitude)
                if lastAltitudeBucket != currentBucket {
                    lastAltitudeBucket = currentBucket
                    lastSegmentsSignature = ""
                    renderedSegments = []
                    map_removeAndRebuildOverlays(mapView)
                    refreshMemoryPinModes(on: mapView)
                }
            }

            if config.useZoomAwareVisibility {
                syncZoomAwareVisibility(on: mapView, animated: true)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.callbacks.onGestureStateChanged?(false)
            }
        }

        private func map_removeAndRebuildOverlays(_ map: MKMapView) {
            map.removeOverlays(routeOverlays)
            routeOverlays.removeAll()
            // Will be rebuilt on next syncAll call via updateUIView
        }

        private func syncZoomAwareVisibility(on mapView: MKMapView, animated: Bool) {
            let shouldShowPins = CityDeepMemoryVisibility.shouldShowPins(latitudeDelta: mapView.region.span.latitudeDelta)

            let applyPinAlpha = {
                for ann in mapView.annotations {
                    guard ann is UnifiedMemoryGroupAnnotation else { continue }
                    mapView.view(for: ann)?.alpha = CityDeepMemoryVisibility.pinAlpha(shouldShowPins: shouldShowPins)
                }
            }

            if animated {
                UIView.animate(withDuration: 0.25) { applyPinAlpha() }
            } else {
                applyPinAlpha()
            }

            for overlay in mapView.overlays {
                guard overlay is UnifiedMemoryDotCircle else { continue }
                mapView.renderer(for: overlay)?.alpha = CityDeepMemoryVisibility.dotAlpha(shouldShowPins: shouldShowPins)
            }
        }
    }
}
