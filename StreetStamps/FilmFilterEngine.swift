import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// =======================================================
// MARK: - Film Filter Engine
// Primary path: .cube LUT (cinematic_teal_orange.cube)
// Fallback: parameter-based CCD chain if LUT unavailable
// =======================================================

enum FilmFilterEngine {

    // MARK: - Shared CIContext

    private static let ciContext: CIContext = {
        if let mtl = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: mtl, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    // MARK: - LUT (lazy, loaded once)

    /// Cached cube data loaded from a film-style .cube LUT in the app bundle.
    /// Currently: MotionVFX **Cold Snap** — cool-cinematic look. Blue-cast
    /// shadows with retained warmth in highlights creates the classic "shot on
    /// a movie" feel (think night-time urban scenes). Picked over Sterling
    /// (more "faded film") and Cadet (more "documentary") for stronger
    /// cinematic character.
    private static let lutData: (data: Data, dimension: Int)? = loadCubeLUT(named: "mlut_cold_snap")

    // MARK: - Public

    /// Full look — for final capture output.
    /// Routes per preset:
    /// • Fuji — film pipeline; `fujiScene` selects indoor vs. outdoor tuning.
    /// • Photobooth — macOS Photo Booth aesthetic via `applyPhotoboothChain`.
    /// • Plain — passthrough.
    static func applyToCapture(
        _ uiImage: UIImage,
        preset: CameraPreset = .fujiCCD,
        fujiScene: FujiScene = .outdoor
    ) -> UIImage {
        guard let cgImage = uiImage.cgImage else { return uiImage }
        let orientation = uiImage.imageOrientation
        let ciInput = CIImage(cgImage: cgImage)

        var result: CIImage
        switch preset {
        case .photobooth:
            result = applyPhotoboothChain(ciInput)
        case .fujiCCD:
            let tuning: FujiTuning = (fujiScene == .indoor) ? .indoor : .outdoor
            result = applyFujiPipeline(ciInput, tuning: tuning)
        case .plain:
            result = ciInput
        }
        result = result.cropped(to: ciInput.extent)

        guard let outputCG = ciContext.createCGImage(result, from: result.extent) else {
            return uiImage
        }
        return UIImage(cgImage: outputCG, scale: uiImage.scale, orientation: orientation)
    }

    // MARK: - Fuji Tuning Profiles

    /// Per-variant FUJI parameters. Color comes from a .cube LUT (configured at
    /// `lutData`); other fields control the spatial / texture effects on top.
    ///
    /// Pipeline order: LUT → WB → sat/contrast → soft focus → flash hot-spot →
    /// grain → vignette. The LUT is the primary color science; everything else
    /// is texture and finishing.
    ///
    /// Fields are `var` and unified as `Double` so the live tuning panel can
    /// bind sliders directly. CIFilter calls cast to `Float` / `CGFloat` at the
    /// call boundary in `applyFujiPipeline`.
    struct FujiTuning: Equatable {
        var lutIntensity: Double        // 0.0 = bypass LUT, 1.0 = full LUT character
        var flashStrength: Double       // 0.0–1.0. Center hot-spot brightness.
        var grainStrength: Double       // 0.04–0.06 typical for visible CCD noise
        var vignetteIntensity: Double   // 0.18–0.26 typical for flash falloff feel
        var saturation: Double          // multiplier on LUT-graded saturation
        var contrast: Double            // multiplier on LUT-graded contrast
        var softFocusRadius: Double     // 0 = skip; 0.6–1.2 typical for CCD softness
        var wbTemperature: Double       // -1.0 cool / 0 neutral / +1.0 warm
        var wbTint: Double              // -1.0 magenta / 0 neutral / +1.0 green

        /// Indoor defaults — calibrated by user via the live tuning panel.
        /// Direction: very light LUT touch (0.165), slight warm WB lift (+0.138)
        /// with anti-green tint (-0.093), modest saturation push, contrast
        /// gently reduced (0.976), some softness + grain for "film" feel.
        /// The flashStrength 0.082 adds a barely-visible center brightening
        /// that mimics ambient indoor "lamp glow" rather than direct flash.
        static let indoor = FujiTuning(
            lutIntensity: 0.165,
            flashStrength: 0.082,
            grainStrength: 0.057,
            vignetteIntensity: 0.037,
            saturation: 1.185,
            contrast: 0.976,
            softFocusRadius: 0.431,
            wbTemperature: 0.138,
            wbTint: -0.093
        )

        /// Outdoor defaults — identical to indoor per user direction. The
        /// indoor/outdoor split is preserved as a UI affordance (the FujiScene
        /// sub-toggle still exists in the viewfinder) but currently both modes
        /// share the same tuning. Tune each independently when you're ready
        /// to differentiate.
        static let outdoor = FujiTuning(
            lutIntensity: 0.165,
            flashStrength: 0.082,
            grainStrength: 0.057,
            vignetteIntensity: 0.037,
            saturation: 1.185,
            contrast: 0.976,
            softFocusRadius: 0.431,
            wbTemperature: 0.138,
            wbTint: -0.093
        )
    }

    // MARK: - Fuji Pipeline (tuning-driven)

    /// FUJI pipeline — color comes from `lutData`, everything else is texture
    /// and finishing on top. WB acts as a final color correction / temperature
    /// nudge after the LUT has done its color science.
    private static func applyFujiPipeline(_ input: CIImage, tuning: FujiTuning) -> CIImage {
        var result = input

        // 1. LUT color grading — primary color science.
        if tuning.lutIntensity > 0, let lut = lutData {
            result = applyLUT(result, data: lut.data, dimension: lut.dimension, intensity: Float(tuning.lutIntensity))
        }

        // 2. White balance — counters iPhone's auto-WB drift and lets the user
        //    nudge the overall image cool/warm and along the green-magenta axis.
        if tuning.wbTemperature != 0 || tuning.wbTint != 0 {
            result = whiteBalance(result, temperature: tuning.wbTemperature, tint: tuning.wbTint)
        }

        // 3. Saturation / contrast — multiplier on top of LUT character.
        result = colorAdjust(result, saturation: Float(tuning.saturation), contrast: Float(tuning.contrast))

        // 4. CCD lens softness.
        if tuning.softFocusRadius > 0 {
            result = softFocus(result, radius: tuning.softFocusRadius)
        }

        // 5. Center flash hot-spot (warm radial brightening).
        if tuning.flashStrength > 0 {
            result = flashHotSpot(result, strength: Float(tuning.flashStrength))
        }

        // 6. CCD-style grain.
        result = ccdGrain(result, strength: CGFloat(tuning.grainStrength))

        // 7. Flash-falloff vignette.
        result = vignette(
            result,
            intensity: CGFloat(tuning.vignetteIntensity),
            radius: vignetteRadius(for: input.extent) * 0.95
        )
        return result
    }

    /// Override entry point used by the live tuning panel. Bypasses scene
    /// lookup and applies the provided tuning directly. Identical to
    /// `applyToCapture(_:preset:fujiScene:)` but skips the preset routing.
    static func applyToCapture(_ uiImage: UIImage, tuning: FujiTuning) -> UIImage {
        guard let cgImage = uiImage.cgImage else { return uiImage }
        let orientation = uiImage.imageOrientation
        let ciInput = CIImage(cgImage: cgImage)

        var result = applyFujiPipeline(ciInput, tuning: tuning)
        result = result.cropped(to: ciInput.extent)

        guard let outputCG = ciContext.createCGImage(result, from: result.extent) else {
            return uiImage
        }
        return UIImage(cgImage: outputCG, scale: uiImage.scale, orientation: orientation)
    }

    // MARK: - White Balance

    /// CITemperatureAndTint with normalized -1..+1 inputs. Negative temperature
    /// shifts cool (blue), positive shifts warm (yellow). Negative tint shifts
    /// magenta, positive shifts green. Source white point is fixed at 6500K.
    private static func whiteBalance(_ input: CIImage, temperature: Double, tint: Double) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = input
        f.neutral = CIVector(x: 6500, y: 0)
        // Map temperature: +1 → 4500K target (image looks warmer),
        //                  -1 → 8500K target (image looks cooler).
        let targetK = 6500 - temperature * 2000
        let tintShift = tint * 100
        f.targetNeutral = CIVector(x: targetK, y: tintShift)
        return f.outputImage ?? input
    }

    // MARK: - Soft Focus

    /// Subtle Gaussian blur emulating the soft optics of small CCD sensors.
    private static func softFocus(_ input: CIImage, radius: Double) -> CIImage {
        let f = CIFilter.gaussianBlur()
        f.inputImage = input
        f.radius = Float(radius)
        return f.outputImage?.cropped(to: input.extent) ?? input
    }

    // MARK: - Flash Hot-Spot

    /// Warm radial gradient soft-light-blended over the image. Soft-light is
    /// much gentler than screen-blend (screen always brightens; soft-light
    /// only nudges based on existing brightness), which is what we need: a
    /// hint of "flash was here", not a blow-out. Color is near-white with a
    /// hair of warmth — strong yellow was over-yellowing the whole frame.
    private static func flashHotSpot(_ input: CIImage, strength: Float) -> CIImage {
        let extent = input.extent
        let radius = Float(min(extent.width, extent.height)) * 0.55

        let radial = CIFilter.radialGradient()
        radial.center = CGPoint(x: extent.midX, y: extent.midY)
        radial.radius0 = 0
        radial.radius1 = radius
        radial.color0 = CIColor(red: 1.00, green: 0.97, blue: 0.93, alpha: CGFloat(strength))
        radial.color1 = CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0)

        guard let gradient = radial.outputImage?.cropped(to: extent) else { return input }

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = gradient
        blend.backgroundImage = input
        return blend.outputImage?.cropped(to: extent) ?? input
    }

    // MARK: - Soft Texture (edge-preserving smoothing)

    /// CINoiseReduction used as a film softener. Smooths uniform regions (skin,
    /// walls, sky) while preserving edges (silhouettes, glasses frames, hair),
    /// which delivers the holistic "natural soft" feel that no global tone or
    /// color tweak can produce. This is the missing ingredient — Dazz/NOMO-class
    /// apps all do something equivalent here.
    private static func softTexture(_ input: CIImage, level: Float) -> CIImage {
        let f = CIFilter.noiseReduction()
        f.inputImage = input
        f.noiseLevel = level
        f.sharpness = 0.40   // higher = preserve more edges; 0.40 is gentle but firm
        return f.outputImage?.cropped(to: input.extent) ?? input
    }

    // MARK: - Color Adjust (post-LUT, parameterized)

    private static func colorAdjust(_ input: CIImage, saturation: Float, contrast: Float) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = input
        f.saturation = saturation
        f.contrast = contrast
        f.brightness = 0
        return f.outputImage ?? input
    }

    // MARK: - Diffusion Glow (parameterized)

    /// CIBloom — softens harsh local contrast by spreading bright pixels.
    /// Caller controls intensity because bloom inherently adds light energy and
    /// should be skipped (or kept very small) where highlights are already crisp.
    private static func diffusionGlow(_ input: CIImage, intensity: Float) -> CIImage {
        let f = CIFilter.bloom()
        f.inputImage = input
        f.radius = 5.0
        f.intensity = intensity
        return f.outputImage?.cropped(to: input.extent) ?? input
    }

    // MARK: - LUT Application (parameterized intensity)

    private static func applyLUT(_ input: CIImage, data: Data, dimension: Int, intensity: Float) -> CIImage {
        // CIColorCube applies the LUT in CoreImage's working linear space without
        // an extra sRGB ↔ linear round-trip (avoids double-gamma overexposure).
        guard let f = CIFilter(name: "CIColorCube") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(dimension, forKey: "inputCubeDimension")
        f.setValue(data as NSData, forKey: "inputCubeData")
        guard let graded = f.outputImage else { return input }

        // Blend LUT result with original at the requested intensity.
        guard let blend = CIFilter(name: "CIDissolveTransition") else { return graded }
        blend.setValue(input, forKey: kCIInputImageKey)
        blend.setValue(graded, forKey: "inputTargetImage")
        blend.setValue(intensity, forKey: kCIInputTimeKey)
        return blend.outputImage?.cropped(to: input.extent) ?? graded
    }

    // MARK: - .cube Parser

    /// Parses a standard 3D .cube file from the app bundle.
    /// Returns (float32 RGBA data, dimension) or nil on failure.
    private static func loadCubeLUT(named name: String) -> (Data, Int)? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "cube"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var dimension = 0
        var floats: [Float] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("TITLE") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                dimension = Int(line.components(separatedBy: .whitespaces).last ?? "") ?? 0
                floats.reserveCapacity(dimension * dimension * dimension * 4)
                continue
            }
            if line.hasPrefix("DOMAIN_") { continue }

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 3,
                  let r = Float(parts[0]),
                  let g = Float(parts[1]),
                  let b = Float(parts[2]) else { continue }
            floats.append(r)
            floats.append(g)
            floats.append(b)
            floats.append(1.0)  // alpha
        }

        guard dimension > 0, floats.count == dimension * dimension * dimension * 4 else {
            return nil
        }

        let data = floats.withUnsafeBytes { Data($0) }
        return (data, dimension)
    }

    // MARK: - Parameter Chain Fallback

    private static func applyParameterChain(_ input: CIImage) -> CIImage {
        var result = input

        let f1 = CIFilter.toneCurve()
        f1.inputImage = result
        f1.point0 = CGPoint(x: 0.0, y: 0.02)
        f1.point1 = CGPoint(x: 0.25, y: 0.245)
        f1.point2 = CGPoint(x: 0.50, y: 0.50)
        f1.point3 = CGPoint(x: 0.75, y: 0.755)
        f1.point4 = CGPoint(x: 1.0, y: 0.97)
        result = f1.outputImage ?? result

        let f2 = CIFilter.temperatureAndTint()
        f2.inputImage = result
        f2.neutral = CIVector(x: 6500, y: 0)
        f2.targetNeutral = CIVector(x: 7300, y: 4)
        result = f2.outputImage ?? result

        let f3 = CIFilter.colorControls()
        f3.inputImage = result
        f3.saturation = 0.90
        f3.brightness = 0.0
        f3.contrast = 0.96
        result = f3.outputImage ?? result

        let bloom = CIFilter.bloom()
        bloom.inputImage = result
        bloom.radius = 5.0
        bloom.intensity = 0.025
        result = bloom.outputImage?.cropped(to: input.extent) ?? result

        return result
    }

    // MARK: - Photobooth Chain

    /// macOS Photo Booth aesthetic — webcam + screen-flash simulation, kept restrained.
    /// Pipeline (all on the downscaled image, then upscaled back):
    ///   1. Downscale (longest edge → `photoboothTargetLongestEdge`).
    ///   2. Mild cool cyan cast — webcam sensor signature under LED screen light.
    ///   3. Tone curve — slight shadow lift, slight highlight roll-off (low DR feel).
    ///   4. Soft bloom — cheap-lens highlight spread, the one webcam-defining cue.
    ///   5. Upscale back; bilinear softness compounds the webcam feel.
    /// Earlier center hot-spot + vignette steps were removed — they compounded with
    /// bloom into a heavy, over-processed look.
    private static let photoboothTargetLongestEdge: CGFloat = 540

    private static func applyPhotoboothChain(_ input: CIImage) -> CIImage {
        let extent = input.extent
        let longest = max(extent.width, extent.height)
        let needsDownscale = longest > photoboothTargetLongestEdge
        let downScale: CGFloat = needsDownscale ? photoboothTargetLongestEdge / longest : 1.0

        // 1. Downscale
        var result: CIImage
        if needsDownscale {
            guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return input }
            lanczos.setValue(input, forKey: kCIInputImageKey)
            lanczos.setValue(downScale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            result = lanczos.outputImage ?? input
        } else {
            result = input
        }
        let smallExtent = result.extent

        // 2. Mild cool cyan cast (≈ half of the earlier biased values)
        let cm = CIFilter.colorMatrix()
        cm.inputImage = result
        cm.rVector = CIVector(x: 0.97, y: 0, z: 0, w: 0)
        cm.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
        cm.bVector = CIVector(x: 0, y: 0, z: 1.0, w: 0)
        cm.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        cm.biasVector = CIVector(x: -0.003, y: 0.020, z: 0.015, w: 0)
        result = cm.outputImage ?? result

        // 3. Gentle webcam tone curve — barely there
        let curve = CIFilter.toneCurve()
        curve.inputImage = result
        curve.point0 = CGPoint(x: 0.00, y: 0.06)
        curve.point1 = CGPoint(x: 0.25, y: 0.27)
        curve.point2 = CGPoint(x: 0.50, y: 0.51)
        curve.point3 = CGPoint(x: 0.75, y: 0.76)
        curve.point4 = CGPoint(x: 1.00, y: 0.97)
        result = curve.outputImage ?? result

        // 4. Soft bloom — the one webcam cue worth keeping (radius/intensity halved)
        let bloom = CIFilter.bloom()
        bloom.inputImage = result
        bloom.radius = 6
        bloom.intensity = 0.10
        result = bloom.outputImage?.cropped(to: smallExtent) ?? result

        // 5. Upscale back to original size
        if needsDownscale {
            let upTransform = CGAffineTransform(scaleX: 1.0 / downScale, y: 1.0 / downScale)
            result = result.transformed(by: upTransform)
        }

        return result.cropped(to: extent)
    }

    // MARK: - Grain & Vignette

    private static func ccdGrain(_ input: CIImage, strength: CGFloat) -> CIImage {
        let extent = input.extent
        guard let noiseRaw = CIFilter(name: "CIRandomGenerator")?.outputImage else { return input }
        let scaledNoise = noiseRaw.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let mono = CIFilter.colorMatrix()
        mono.inputImage = scaledNoise
        let s = Float(strength)
        mono.rVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(s * 0.6))
        mono.gVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(s * 0.6))
        mono.bVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(s * 0.6))
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: CGFloat(-s * 0.3), y: CGFloat(-s * 0.3), z: CGFloat(-s * 0.3), w: 1)
        guard let grain = mono.outputImage?.cropped(to: extent) else { return input }
        let blend = CIFilter.additionCompositing()
        blend.inputImage = grain
        blend.backgroundImage = input
        return blend.outputImage?.cropped(to: extent) ?? input
    }

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
