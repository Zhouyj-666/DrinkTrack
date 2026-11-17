import AVFoundation
import SwiftUI
import UIKit

enum FriendQRScannerSupport {
    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static var hasCameraHardware: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// Camera preview that reads the 6-digit friend-code QR. No network calls.
struct FriendQRScannerView: View {
    var onFoundCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hint = "将好友的二维码放入框内"

    var body: some View {
        NavigationStack {
            ZStack {
                FriendQRScannerPreview(
                    onFound: handleScan,
                    onSetupFailed: {
                        hint = "无法打开相机，请返回手动输入 6 位好友码。"
                    }
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text(hint)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 28)
                }
            }
            .background(Color.black)
            .navigationTitle("扫一扫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func handleScan(_ raw: String) {
        if let code = FriendCodeParser.code(fromQRPayload: raw) {
            onFoundCode(code)
            dismiss()
        } else {
            hint = "无法识别这是好友码，请对准 6 位数字二维码，或返回手动输入。"
        }
    }
}

private struct FriendQRScannerPreview: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onSetupFailed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound, onSetupFailed: onSetupFailed)
    }

    func makeUIViewController(context: Context) -> FriendQRScannerViewController {
        let controller = FriendQRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: FriendQRScannerViewController, context: Context) {
        context.coordinator.onFound = onFound
        context.coordinator.onSetupFailed = onSetupFailed
    }

    final class Coordinator: FriendQRScannerDelegate {
        var onFound: (String) -> Void
        var onSetupFailed: () -> Void
        private var didEmitValidCode = false

        init(onFound: @escaping (String) -> Void, onSetupFailed: @escaping () -> Void) {
            self.onFound = onFound
            self.onSetupFailed = onSetupFailed
        }

        func scannerDidFailToSetUp() {
            onSetupFailed()
        }

        func scannerDidRead(_ payload: String) {
            // Keep reading until a valid 6-digit friend code is in the frame.
            if didEmitValidCode { return }
            if FriendCodeParser.code(fromQRPayload: payload) != nil {
                didEmitValidCode = true
            }
            onFound(payload)
        }
    }
}

protocol FriendQRScannerDelegate: AnyObject {
    func scannerDidFailToSetUp()
    func scannerDidRead(_ payload: String)
}

final class FriendQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: FriendQRScannerDelegate?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.scannerDidFailToSetUp()
            }
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.scannerDidFailToSetUp()
            }
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        } else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.scannerDidFailToSetUp()
            }
            return
        }

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let value = readable.stringValue,
                  !value.isEmpty else { continue }
            delegate?.scannerDidRead(value)
            return
        }
    }
}
