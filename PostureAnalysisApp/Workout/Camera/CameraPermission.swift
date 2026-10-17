import AVFoundation
import Foundation

enum CameraAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
protocol CameraPermissionProviding {
    var status: CameraAuthorization { get }
    func request(_ completion: @escaping @MainActor (Bool) -> Void)
}

@MainActor
struct SystemCameraPermission: CameraPermissionProviding {
    var status: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in completion(granted) }
        }
    }
}
