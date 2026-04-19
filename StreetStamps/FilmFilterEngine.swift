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

    /// Cached cube data loaded from cinematic_teal_orange.cube in the app bundle.
    private static let lutData: (data: Data, dimension: Int)? = loadCubeLUT(named: "cinematic_natural_v3")

    // MARK: - Public

    /// Full look — for final capture output.
    /// Uses the .cube LUT when available; falls back to parameter chain otherwise.
    static func applyToCapture(_ uiImage: UIImage) -> UIImage {
        guard let cgImage = uiImage.cgImage else { return uiImage }
        let orientation = uiImage.imageOrientation
        let ciInput = CIImage(cgImage: cgImage)

        var result: CIImage
        if let lut = lutData {
            result = applyLUT(ciInput, data: lut.data, dimension: lut.dimension)
        } else {
            result = applyParameterChain(ciInput)
        }

        // Grain and vignette always run on top of the color grade
        result = ccdGrain(result, strength: 0.006)
        result = vignette(result, intensity: 0.07, radius: vignetteRadius(for: ciInput.extent))
        result = result.cropped(to: ciInput.extent)

        guard let outputCG = ciContext.createCGImage(result, from: result.extent) else {
            return uiImage
        }
        return UIImage(cgImage: outputCG, scale: uiImage.scale, orientation: orientation)
    }

    // MARK: - LUT Application

    /// intensity: 0 = original, 1 = full LUT. 0.55 keeps the look without crushing the image.
    private static let lutIntensity: Float = 0.55

    private static func applyLUT(_ input: CIImage, data: Data, dimension: Int) -> CIImage {
        // CIColorCube (no inputColorSpace) applies the LUT in CoreImage's working linear space
        // without an extra sRGB ↔ linear round-trip, which avoids double-gamma overexposure.
        guard let f = CIFilter(name: "CIColorCube") else { return input }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(dimension, forKey: "inputCubeDimension")
        f.setValue(data as NSData, forKey: "inputCubeData")
        guard let graded = f.outputImage else { return input }

        // Blend LUT result with original at lutIntensity to tame extreme looks
        guard let blend = CIFilter(name: "CIDissolveTransition") else { return graded }
        blend.setValue(input, forKey: kCIInputImageKey)
        blend.setValue(graded, forKey: "inputTargetImage")
        blend.setValue(lutIntensity, forKey: kCIInputTimeKey)
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
