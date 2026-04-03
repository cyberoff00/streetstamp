import MapKit

/// A styled MKPolyline carrying rendering metadata used by LayeredPolylineRenderer.
final class StyledPolyline: MKPolyline {
    var isGap: Bool = false
    var repeatWeight: Double = 0
}

/// Stacks multiple MKPolylineRenderers into one overlay, optionally adding a
/// blur-shadow glow on the first (bottom-most) layer for dark-mode highlighting.
final class LayeredPolylineRenderer: MKOverlayRenderer {
    private let renderers: [MKPolylineRenderer]
    var glowBlur: CGFloat = 0
    var glowColor: CGColor?

    init(renderers: [MKPolylineRenderer]) {
        precondition(!renderers.isEmpty)
        self.renderers = renderers
        super.init(overlay: renderers[0].overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        for (i, renderer) in renderers.enumerated() {
            if i == 0, glowBlur > 0, let color = glowColor {
                context.saveGState()
                context.setShadow(offset: .zero, blur: glowBlur / zoomScale, color: color)
                renderer.draw(mapRect, zoomScale: zoomScale, in: context)
                context.restoreGState()
            } else {
                renderer.draw(mapRect, zoomScale: zoomScale, in: context)
            }
        }
    }
}
