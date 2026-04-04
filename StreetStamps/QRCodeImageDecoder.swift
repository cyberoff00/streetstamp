import UIKit
import Vision

enum QRCodeImageDecoder {
    static func decode(image: UIImage) -> String? {
        guard let cgImage = image.cgImage ?? ciImageToCGImage(image.ciImage) else { return nil }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let results = request.results else { return nil }
        for observation in results {
            let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let payload, !payload.isEmpty {
                return payload
            }
        }
        return nil
    }

    private static func ciImageToCGImage(_ ciImage: CIImage?) -> CGImage? {
        guard let ciImage else { return nil }
        return CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent)
    }
}
