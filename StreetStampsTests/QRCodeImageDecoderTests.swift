import XCTest
import CoreImage
import UIKit
@testable import StreetStamps

final class QRCodeImageDecoderTests: XCTestCase {
    func test_decode_returnsPayloadForQRCodeImage() {
        let payload = "streetstamps://add-friend?code=ABCD1234"
        let image = try XCTUnwrap(makeQRCodeImage(from: payload))

        let decoded = QRCodeImageDecoder.decode(image: image)

        XCTAssertEqual(decoded, payload)
    }

    func test_decode_returnsNilForPlainImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
        let image = renderer.image { ctx in
            UIColor.systemMint.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 240, height: 240)))
        }

        let decoded = QRCodeImageDecoder.decode(image: image)

        XCTAssertNil(decoded)
    }

    private func makeQRCodeImage(from text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
