import UIKit
import CoreImage

enum QRCodeImageDecoder {
    static func decode(image: UIImage) -> String? {
        guard let ciImage = ciImage(from: image) else { return nil }

        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: CIContext(options: nil),
            options: options
        ) else {
            return nil
        }

        let features = detector.features(in: ciImage)
        for case let qr as CIQRCodeFeature in features {
            let payload = qr.messageString?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let payload, !payload.isEmpty {
                return payload
            }
        }
        return nil
    }

    private static func ciImage(from image: UIImage) -> CIImage? {
        if let ciImage = image.ciImage {
            return ciImage
        }
        if let cgImage = image.cgImage {
            return CIImage(cgImage: cgImage)
        }
        return nil
    }
}
