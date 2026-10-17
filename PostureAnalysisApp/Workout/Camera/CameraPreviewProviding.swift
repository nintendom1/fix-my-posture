import AVFoundation

protocol CameraPreviewProviding: AnyObject {
    @MainActor var previewSession: AVCaptureSession? { get }
}
