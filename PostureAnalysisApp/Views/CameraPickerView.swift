import SwiftUI
import UIKit

public struct CameraPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    public var onCapture: (UIImage, Bool, HorizonReading?) -> Void
    private let monitor: HorizonMonitoring

    public init(
        monitor: HorizonMonitoring = CoreMotionHorizonMonitor(),
        onCapture: @escaping (UIImage, Bool, HorizonReading?) -> Void
    ) {
        self.monitor = monitor
        self.onCapture = onCapture
    }

    public init(onImageCaptured: @escaping (UIImage) -> Void) {
        self.init(monitor: CoreMotionHorizonMonitor()) { image, _, _ in
            onImageCaptured(image)
        }
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            monitor.startUpdates()
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    public static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        coordinator.monitor.stopUpdates()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self, monitor: monitor)
    }

    public class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        let monitor: HorizonMonitoring

        init(_ parent: CameraPickerView, monitor: HorizonMonitoring) {
            self.parent = parent
            self.monitor = monitor
        }

        public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let isCamera = (picker.sourceType == .camera)
            let isFront = (picker.cameraDevice == .front)
            let rawReading = isCamera ? monitor.latestReading : nil

            if let image = info[.originalImage] as? UIImage {
                let transformedReading = rawReading.map { r in
                    HorizonReading(
                        angleDegrees: HorizonGeometry.capturedImageAngle(r.angleDegrees, isFrontCamera: isFront, orientation: image.imageOrientation),
                        timestamp: r.timestamp,
                        gravityMagnitude: r.gravityMagnitude
                    )
                }
                parent.onCapture(image, isCamera, transformedReading)
            }
            monitor.stopUpdates()
            parent.dismiss()
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            monitor.stopUpdates()
            parent.dismiss()
        }
    }
}
