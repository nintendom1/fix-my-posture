import AVFoundation

/// Shared portrait capture configuration for live pose features.
/// Buffers are rotated upright and explicitly unmirrored; only previews mirror the selfie view.
enum PortraitCameraSession {
    /// Call on the capture queue with the session stopped. Returns a user-facing failure message, or nil on success.
    static func configure(
        session: AVCaptureSession,
        output: AVCaptureVideoDataOutput,
        position: AVCaptureDevice.Position,
        delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        queue: DispatchQueue
    ) -> String? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return "Camera hardware is unavailable. Try again on an iPhone with a camera."
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(delegate, queue: queue)
        guard session.canAddOutput(output) else {
            return "Unable to read camera frames. Close this screen and try again."
        }
        session.addOutput(output)
        guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) else {
            return "This camera does not support portrait tracking."
        }
        connection.videoRotationAngle = 90
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        return nil
    }
}
