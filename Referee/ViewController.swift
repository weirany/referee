import UIKit
import AVFoundation

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var apiKeyButton: UIButton!
    @IBOutlet weak var takePhotoButton: UIButton!
    
    let userDefaultsKey = "OpenAIKey"
    
    let captureSession = AVCaptureSession()
    var photoOutput = AVCapturePhotoOutput()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateButtonAndTakePhotoButtonState()
        setupCameraSession()
    }
    
    @IBAction func apiKeyButtonTapped(_ sender: UIButton) {
        if UserDefaults.standard.string(forKey: userDefaultsKey) != nil {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            updateButtonAndTakePhotoButtonState()
        } else {
            let alert = UIAlertController(title: "Enter API Key", message: nil, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.placeholder = "API Key"
            }
            let submitAction = UIAlertAction(title: "Submit", style: .default) { [unowned alert] _ in
                let textField = alert.textFields![0]
                if let apiKey = textField.text, !apiKey.isEmpty {
                    UserDefaults.standard.set(apiKey, forKey: self.userDefaultsKey)
                    self.updateButtonAndTakePhotoButtonState()
                }
            }
            alert.addAction(submitAction)
            present(alert, animated: true)
        }
    }
    
    func updateButtonAndTakePhotoButtonState() {
        if UserDefaults.standard.string(forKey: userDefaultsKey) != nil {
            apiKeyButton.setTitle("Clear OpenAI Key", for: .normal)
            takePhotoButton.isEnabled = true
        } else {
            apiKeyButton.setTitle("Enter OpenAI Key", for: .normal)
            takePhotoButton.isEnabled = false
        }
    }
    
    func setupCameraSession() {
        captureSession.beginConfiguration()
        
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        guard let backCamera = deviceDiscoverySession.devices.first,
              let input = try? AVCaptureDeviceInput(device: backCamera) else {
            print("Failed to get the camera device")
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        captureSession.commitConfiguration()
    }
    
    @IBAction func takePhoto(_ sender: UIButton) {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = .auto
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData),
           let croppedImage = cropToSquare(image: image) {
            // Resize the image to 512x512 pixels
            let resizedImage = resizeImage(image: croppedImage, targetSize: CGSize(width: 512, height: 512))
            imageView.image = resizedImage
            //            let base64String = resizedImage.jpegData(compressionQuality: 1.0)?.base64EncodedString()
            //            print(base64String ?? "Error in image conversion")
        }
    }
    
    func cropToSquare(image: UIImage) -> UIImage? {
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        let cropSize = min(originalWidth, originalHeight)
        
        let cropRect = CGRect(
            x: (originalWidth - cropSize) / 2.0,
            y: (originalHeight - cropSize) / 2.0,
            width: cropSize,
            height: cropSize
        )
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: cropSize, height: cropSize), false, image.scale)
        image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        let croppedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return croppedImage
    }
    
    
    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let newSize = widthRatio > heightRatio ? CGSize(width: size.width * heightRatio, height: size.height * heightRatio) : CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
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
