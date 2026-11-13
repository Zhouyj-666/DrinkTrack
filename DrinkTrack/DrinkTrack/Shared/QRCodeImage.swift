import SwiftUI
import CoreImage.CIFilterBuiltins

/// 把一段文字画成本机二维码，用于展示和分享好友码。不发起任何网络请求。
enum QRCodeImage {
    static func make(from string: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView: View {
    let value: String
    var side: CGFloat = 180

    var body: some View {
        Group {
            if let image = QRCodeImage.make(from: value) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .padding(8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("好友码二维码")
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: side * 0.4))
                    .foregroundStyle(DesignSystem.mutedInk)
                    .frame(width: side, height: side)
            }
        }
    }
}
