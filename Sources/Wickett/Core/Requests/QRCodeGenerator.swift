import UIKit
import CoreImage

/// Utility for generating QR codes
class QRCodeGenerator {

    /// Generate QR code image from string
    /// - Parameters:
    ///   - string: The string to encode (Solana Pay URL or deep link)
    ///   - size: Desired size of QR code image
    /// - Returns: UIImage of QR code, or nil if generation fails
    static func generateQRCode(from string: String, size: CGSize = CGSize(width: 300, height: 300)) -> UIImage? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        // Create QR code filter
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction

        guard let ciImage = filter.outputImage else {
            return nil
        }

        // Scale up the QR code to desired size
        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let transformedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Convert to UIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Generate QR code for payment request (Solana Pay format)
    /// - Parameter request: Payment request to encode
    /// - Returns: UIImage of QR code
    static func generateQRCode(for request: PaymentRequest, size: CGSize = CGSize(width: 300, height: 300)) -> UIImage? {
        return generateQRCode(from: request.solanaPay, size: size)
    }

    /// Generate QR code for deep link
    /// - Parameter request: Payment request to encode
    /// - Returns: UIImage of QR code for app deep link
    static func generateDeepLinkQRCode(for request: PaymentRequest, size: CGSize = CGSize(width: 300, height: 300)) -> UIImage? {
        return generateQRCode(from: request.shareableLink, size: size)
    }
}
