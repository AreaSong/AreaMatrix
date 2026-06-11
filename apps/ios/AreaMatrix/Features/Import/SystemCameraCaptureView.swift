import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

struct SystemCameraCaptureUnavailable: Equatable, Sendable {
    var message: String
    var canOpenSettings: Bool

    static let cameraUnavailable = SystemCameraCaptureUnavailable(
        message: "Camera capture is available on iOS.",
        canOpenSettings: false
    )

    static let permissionDenied = SystemCameraCaptureUnavailable(
        message: "Camera access is required to take a photo.",
        canOpenSettings: true
    )

    static let capturedPhotoUnreadable = SystemCameraCaptureUnavailable(
        message: "Could not read captured photo.",
        canOpenSettings: false
    )
}

enum SystemCameraCaptureAvailability {
    @MainActor
    static func requestCameraAccess() async -> SystemCameraCaptureUnavailable? {
        #if os(iOS)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .cameraUnavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return nil
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return await requestVideoAccess()
        @unknown default:
            return .permissionDenied
        }
        #else
        return .cameraUnavailable
        #endif
    }

    #if os(iOS)
    private static func requestVideoAccess() async -> SystemCameraCaptureUnavailable? {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted ? nil : .permissionDenied)
            }
        }
    }
    #endif
}

enum SystemCapturedPhotoStore {
    private static let filenamePrefix = "AreaMatrixCapturedPhoto-"

    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filenamePrefix)\(UUID().uuidString).jpg")
    }

    static func discardIfOwned(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent() == temporaryDirectory,
              standardizedURL.lastPathComponent.hasPrefix(filenamePrefix),
              standardizedURL.pathExtension.lowercased() == "jpg" else {
            return
        }
        try? FileManager.default.removeItem(at: standardizedURL)
    }
}

extension View {
    func systemCameraCapture(
        isPresented: Binding<Bool>,
        onCaptured: @escaping (URL) -> Void,
        onUnavailable: @escaping (SystemCameraCaptureUnavailable) -> Void
    ) -> some View {
        modifier(SystemCameraCaptureModifier(
            isPresented: isPresented,
            onCaptured: onCaptured,
            onUnavailable: onUnavailable
        ))
    }
}

private struct SystemCameraCaptureModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onCaptured: (URL) -> Void
    let onUnavailable: (SystemCameraCaptureUnavailable) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented) {
            SystemCameraCaptureView(
                onCaptured: { url in
                    isPresented = false
                    onCaptured(url)
                },
                onCancel: { isPresented = false },
                onUnavailable: { message in
                    isPresented = false
                    onUnavailable(message)
                }
            )
        }
        #else
        content.onChange(of: isPresented) { _, value in
            guard value else { return }
            isPresented = false
            onUnavailable(.cameraUnavailable)
        }
        #endif
    }
}

#if os(iOS)
private struct SystemCameraCaptureView: UIViewControllerRepresentable {
    let onCaptured: (URL) -> Void
    let onCancel: () -> Void
    let onUnavailable: (SystemCameraCaptureUnavailable) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            DispatchQueue.main.async {
                onUnavailable(.cameraUnavailable)
            }
        }
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptured: onCaptured, onCancel: onCancel, onUnavailable: onUnavailable)
    }
}

private final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onCaptured: (URL) -> Void
    private let onCancel: () -> Void
    private let onUnavailable: (SystemCameraCaptureUnavailable) -> Void

    init(
        onCaptured: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onUnavailable: @escaping (SystemCameraCaptureUnavailable) -> Void
    ) {
        self.onCaptured = onCaptured
        self.onCancel = onCancel
        self.onUnavailable = onUnavailable
    }

    func imagePickerControllerDidCancel(_: UIImagePickerController) {
        onCancel()
    }

    func imagePickerController(
        _: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.92),
              let url = try? writeCapturedPhoto(data) else {
            onUnavailable(.capturedPhotoUnreadable)
            return
        }
        onCaptured(url)
    }

    private func writeCapturedPhoto(_ data: Data) throws -> URL {
        let url = SystemCapturedPhotoStore.temporaryURL()
        try data.write(to: url, options: .atomic)
        return url
    }
}
#endif
