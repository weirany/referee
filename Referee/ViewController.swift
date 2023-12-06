import UIKit
import AVFoundation

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {

    let captureSession = AVCaptureSession()
    var frontCamera: AVCaptureDevice?
    var photoOutput = AVCapturePhotoOutput()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCameraSession()
    }

    func setupCameraSession() {
        captureSession.beginConfiguration()
        
        // Setting up the device
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        guard let frontCamera = deviceDiscoverySession.devices.first,
              let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("Failed to get the camera device")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Setting up the output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
    }

    @IBAction func takePhoto(_ sender: UIButton) {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = .auto // or .off, .on based on your requirement
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData) {
            // Here you have your image
            let base64String = image.jpegData(compressionQuality: 1.0)?.base64EncodedString()
            print(base64String ?? "Error in image conversion")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.stopRunning()
        }
    }
}
