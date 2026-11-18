@preconcurrency import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit

enum DiagnosticCaptureMode: String, Sendable {
    case tongue
    case face

    var navigationTitle: String {
        switch self {
        case .tongue: return "标准化舌象采集"
        case .face: return "自然光素颜面色采集"
        }
    }

    var guidanceTitle: String {
        switch self {
        case .tongue: return "减少舌苔色偏的三条拍照原则"
        case .face: return "还原真实面色的三条拍照原则"
        }
    }

    var guidanceSteps: String {
        switch self {
        case .tongue:
            return "1. 请面向窗户等自然白光，避开暖黄台灯或强背光。\n2. 勿使用美颜、滤镜，以免抹掉舌苔厚腻感与齿痕。\n3. 自然伸舌 2 秒，对准框内即可拍摄。"
        case .face:
            return "1. 素颜面向自然白光，避开有色灯光与美颜滤镜。\n2. 摘掉反光眼镜，面部放松平视镜头（看面色光泽、浮肿或潮红）。\n3. 若当前已带妆或不便拍照，可直接关闭跳过。"
        }
    }

    var overlayPrompt: String {
        switch self {
        case .tongue: return "请将舌面置于虚线框内"
        case .face: return "请将面部置于虚线框内"
        }
    }

    var overlaySize: CGSize {
        switch self {
        case .tongue: return CGSize(width: 150, height: 195)
        case .face: return CGSize(width: 205, height: 255)
        }
    }

    var captureButtonTitle: String {
        switch self {
        case .tongue: return "拍摄舌象"
        case .face: return "拍摄面色"
        }
    }

    var pickerButtonTitle: String {
        switch self {
        case .tongue: return "从相册选择舌象照片"
        case .face: return "从相册选择素颜面色照"
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .tongue: return "使用这张舌象"
        case .face: return "使用这张面色照"
        }
    }
}

enum TonguePhotoQuality: Sendable {
    case good(brightness: Double)
    case tooDark(brightness: Double)
    case tooBright(brightness: Double)

    var statusText: String {
        switch self {
        case .good:
            return "自然光照度良好，可用于舌质与舌苔辨识"
        case .tooDark:
            return "画面偏暗，可能把淡白舌误判为暗紫，建议移至明亮自然光下重拍"
        case .tooBright:
            return "画面过曝，可能冲淡舌苔厚腻细节，建议避开强直射光重拍"
        }
    }

    var isWarning: Bool {
        if case .good = self { return false }
        return true
    }

    static func evaluate(_ image: UIImage) -> TonguePhotoQuality {
        guard let cgImage = image.cgImage else { return .good(brightness: 0.5) }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter?.outputImage else {
            return .good(brightness: 0.5)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        if luminance < 0.20 {
            return .tooDark(brightness: luminance)
        } else if luminance > 0.88 {
            return .tooBright(brightness: luminance)
        }
        return .good(brightness: luminance)
    }
}

@MainActor
@Observable
final class TongueCameraController: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .front
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var permissionDenied: Bool = false

    func startIfAuthorized() async {
        guard isCameraAvailable else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                configureAndStart()
            } else {
                permissionDenied = true
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    func stop() {
        let captureSession = session
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.stopRunning()
            }
        }
    }

    func switchCamera() {
        currentPosition = (currentPosition == .front) ? .back : .front
        isConfigured = false
        configureAndStart()
    }

    func capturePhoto() async -> UIImage? {
        guard isConfigured else { return nil }
        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureAndStart() {
        let desiredPosition = currentPosition
        let captureSession = session
        let output = photoOutput

        if !isConfigured {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .photo

            for existing in captureSession.inputs {
                captureSession.removeInput(existing)
            }

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: desiredPosition)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

            if let device {
                try? device.lockForConfiguration()
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()

                if let input = try? AVCaptureDeviceInput(device: device),
                   captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
            }

            if !captureSession.outputs.contains(output), captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
            }
            captureSession.commitConfiguration()
            isConfigured = true
        }

        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }
    }
}

extension TongueCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if let data, let image = UIImage(data: data) {
                self.photoContinuation?.resume(returning: image)
            } else {
                self.photoContinuation?.resume(returning: nil)
            }
            self.photoContinuation = nil
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

struct TongueCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: DiagnosticCaptureMode
    let onConfirmImage: (UIImage, TonguePhotoQuality) -> Void

    init(
        mode: DiagnosticCaptureMode = .tongue,
        onConfirmImage: @escaping (UIImage, TonguePhotoQuality) -> Void
    ) {
        self.mode = mode
        self.onConfirmImage = onConfirmImage
    }

    @State private var camera = TongueCameraController()
    @State private var capturedImage: UIImage?
    @State private var quality: TonguePhotoQuality?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCapturing: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guidanceBanner

                    if let capturedImage {
                        capturedPreviewCard(image: capturedImage)
                    } else {
                        cameraStageCard
                    }
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        camera.stop()
                        dismiss()
                    }
                    .foregroundStyle(AuraTheme.secondaryText)
                }
            }
            .task {
                await camera.startIfAuthorized()
            }
            .onDisappear {
                camera.stop()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        capturedImage = image
                        quality = TonguePhotoQuality.evaluate(image)
                    }
                }
            }
        }
    }

    private var guidanceBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(mode.guidanceTitle, systemImage: "sun.max.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)

            Text(mode.guidanceSteps)
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var cameraStageCard: some View {
        if camera.isCameraAvailable && !camera.permissionDenied {
            VStack(spacing: 14) {
                ZStack {
                    CameraPreviewView(session: camera.session)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    RoundedRectangle(cornerRadius: 80, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: mode.overlaySize.width, height: mode.overlaySize.height)

                    VStack {
                        Spacer()
                        Text(mode.overlayPrompt)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, 12)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        camera.switchCamera()
                    } label: {
                        Label("切镜头", systemImage: "arrow.triangle.2.circlepath.camera")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AuraTheme.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AuraTheme.subtleSurface, in: Capsule())
                    }

                    Button {
                        Task {
                            isCapturing = true
                            defer { isCapturing = false }
                            if let image = await camera.capturePhoto() {
                                capturedImage = image
                                quality = TonguePhotoQuality.evaluate(image)
                                HapticFeedback.impact(.medium)
                            }
                        }
                    } label: {
                        Label(isCapturing ? "采集中…" : mode.captureButtonTitle, systemImage: "camera.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(AuraTheme.sageGreen, in: Capsule())
                    }
                    .disabled(isCapturing)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("相册", systemImage: "photo")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AuraTheme.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AuraTheme.subtleSurface, in: Capsule())
                    }
                }
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(AuraTheme.sageGreen)

                Text(camera.permissionDenied ? "未获得相机权限" : "当前设备未检测到可用摄像头（如模拟器）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTheme.primaryText)

                Text("你可以直接从相册选择自然光下拍摄的\(mode == .tongue ? "舌象" : "素颜面色")照片，系统会自动校验画面照度。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
                    .multilineTextAlignment(.center)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(mode.pickerButtonTitle, systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AuraTheme.sageGreen, in: Capsule())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        }
    }

    private func capturedPreviewCard(image: UIImage) -> some View {
        let resolvedQuality = quality ?? TonguePhotoQuality.evaluate(image)

        return VStack(alignment: .leading, spacing: 14) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: resolvedQuality.isWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(resolvedQuality.isWarning ? AuraTheme.warmGinger : AuraTheme.sageGreen)
                    .padding(.top, 2)

                Text(resolvedQuality.statusText)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (resolvedQuality.isWarning ? AuraTheme.warmGinger : AuraTheme.sageGreen).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            HStack(spacing: 12) {
                Button {
                    capturedImage = nil
                    quality = nil
                    selectedPhotoItem = nil
                } label: {
                    Text("重拍 / 重选")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AuraTheme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AuraTheme.subtleSurface, in: Capsule())
                }

                Button {
                    HapticFeedback.notify(.success)
                    onConfirmImage(image, resolvedQuality)
                    camera.stop()
                    dismiss()
                } label: {
                    Text(mode.confirmButtonTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AuraTheme.sageGreen, in: Capsule())
                }
            }
        }
        .padding(14)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }
}

#Preview {
    TongueCaptureSheet { _, _ in }
}
