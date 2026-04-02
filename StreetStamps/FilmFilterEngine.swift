import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// =======================================================
// MARK: - Film Filter Engine
// Sakura CCD Soft — warm sunlight, airy shadows,
// soft highlight bloom, restrained color, fine digital grain.
// Reference: early Fuji compact digital output with soft diffusion.
// =======================================================

enum FilmFilterEngine {
    struct CaptureLookTuning {
        let tonePoint0: CGPoint
        let tonePoint1: CGPoint
        let tonePoint2: CGPoint
        let tonePoint3: CGPoint
        let tonePoint4: CGPoint
        let targetNeutral: CIVector
        let saturation: Float
        let brightness: Float
        let contrast: Float
        let bloomRadius: CGFloat
        let bloomIntensity: CGFloat
        let grainStrength: CGFloat
        let vignetteIntensity: CGFloat

        static let sakuraCCDSoft = CaptureLookTuning(
            tonePoint0: CGPoint(x: 0.0, y: 0.04),
            tonePoint1: CGPoint(x: 0.25, y: 0.25),
            tonePoint2: CGPoint(x: 0.50, y: 0.50),
            tonePoint3: CGPoint(x: 0.75, y: 0.74),
            tonePoint4: CGPoint(x: 1.0, y: 0.94),
            targetNeutral: CIVector(x: 6350, y: -6),
            saturation: 0.94,
            brightness: 0.0,
            contrast: 1.0,
            bloomRadius: 8.0,
            bloomIntensity: 0.055,
            grainStrength: 0.010,
            vignetteIntensity: 0.12
        )
    }

    private static let ciContext: CIContext = {
        if let mtl = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtl, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    // MARK: - Public

    /// Full CCD look — for final capture output
    static func applyToCapture(_ uiImage: UIImage) -> UIImage {
        guard let cgImage = uiImage.cgImage else { return uiImage }
        let orientation = uiImage.imageOrientation
        let ciInput = CIImage(cgImage: cgImage)
        let tuning = CaptureLookTuning.sakuraCCDSoft

        var result = ciInput

        // 1. Tone: lifted blacks and a soft shoulder to keep sunlight airy
        result = toneCurve(result, tuning: tuning)

        // 2. White balance: warm overall, slightly green to keep skin from going yellow
        result = warmthShift(result, tuning: tuning)

        // 3. Color: restrained saturation and softened contrast
        result = colorPunch(result, tuning: tuning)

        // 4. Highlight bloom: bright areas should glow rather than fog the whole frame
        result = highlightBloom(result, radius: tuning.bloomRadius, intensity: tuning.bloomIntensity)

        // 5. Fine CCD grain (uniform, not coarse film grain)
        result = ccdGrain(result, strength: tuning.grainStrength)

        // 6. Very subtle vignette — natural falloff only
        result = vignette(
            result,
            intensity: tuning.vignetteIntensity,
            radius: vignetteRadius(for: ciInput.extent)
        )

        result = result.cropped(to: ciInput.extent)

        guard let outputCG = ciContext.createCGImage(result, from: result.extent) else {
            return uiImage
        }
        return UIImage(cgImage: outputCG, scale: uiImage.scale, orientation: orientation)
    }

    /// Lightweight version for live preview tint (no grain/bloom)
    static func previewTintColor() -> UIColor {
        // A very subtle warm overlay to hint at the filter in live preview
        UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 0.045)
    }

    // MARK: - Filter Components

    /// Soft CCD tone curve: airy shadows, gentle midtones, soft highlight rolloff
    private static func toneCurve(_ input: CIImage, tuning: CaptureLookTuning) -> CIImage {
        let f = CIFilter.toneCurve()
        f.inputImage = input
        f.point0 = tuning.tonePoint0
        f.point1 = tuning.tonePoint1
        f.point2 = tuning.tonePoint2
        f.point3 = tuning.tonePoint3
        f.point4 = tuning.tonePoint4
        return f.outputImage ?? input
    }

    /// Warm but slightly green-balanced shift to preserve clean skin tones
    private static func warmthShift(_ input: CIImage, tuning: CaptureLookTuning) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = input
        f.neutral = CIVector(x: 6500, y: 0)
        f.targetNeutral = tuning.targetNeutral
        return f.outputImage ?? input
    }

    /// Restrained color response to keep greens and reds from feeling too modern
    private static func colorPunch(_ input: CIImage, tuning: CaptureLookTuning) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = input
        f.saturation = tuning.saturation
        f.brightness = tuning.brightness
        f.contrast = tuning.contrast
        return f.outputImage ?? input
    }

    /// CCD highlight bloom — light bleeds around bright areas
    private static func highlightBloom(_ input: CIImage, radius: CGFloat, intensity: CGFloat) -> CIImage {
        let f = CIFilter.bloom()
        f.inputImage = input
        f.radius = Float(radius)
        f.intensity = Float(intensity)
        return f.outputImage?.cropped(to: input.extent) ?? input
    }

    /// CCD-style grain: fine, uniform digital noise (not coarse film grain)
    private static func ccdGrain(_ input: CIImage, strength: CGFloat) -> CIImage {
        let extent = input.extent

        guard let noiseRaw = CIFilter(name: "CIRandomGenerator")?.outputImage else { return input }

        // Scale noise down for finer grain pattern
        let scaleTransform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let scaledNoise = noiseRaw.transformed(by: scaleTransform)

        // Make monochrome + control strength
        let mono = CIFilter.colorMatrix()
        mono.inputImage = scaledNoise
        let s = Float(strength)
        // Use luminance coefficients for natural-looking monochrome noise
        mono.rVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: CGFloat(s * 0.6))
        mono.gVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: CGFloat(s * 0.6))
        mono.bVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: CGFloat(s * 0.6))
        mono.aVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: 0.0)
        mono.biasVector = CIVector(x: CGFloat(-s * 0.3), y: CGFloat(-s * 0.3), z: CGFloat(-s * 0.3), w: 1.0)

        guard let grainLayer = mono.outputImage?.cropped(to: extent) else { return input }

        let blend = CIFilter.additionCompositing()
        blend.inputImage = grainLayer
        blend.backgroundImage = input
        return blend.outputImage?.cropped(to: extent) ?? input
    }

    /// Subtle optical vignette
    private static func vignette(_ input: CIImage, intensity: CGFloat, radius: CGFloat) -> CIImage {
        let f = CIFilter.vignette()
        f.inputImage = input
        f.intensity = Float(intensity)
        f.radius = Float(radius)
        return f.outputImage ?? input
    }

    static func vignetteRadius(for extent: CGRect) -> CGFloat {
        min(extent.width, extent.height) * 0.82
    }
}
