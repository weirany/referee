import AVFoundation
import Foundation
import GoogleGenerativeAI
import UIKit

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var openAIKeyButton: UIButton!
    @IBOutlet weak var geminiKeyButton: UIButton!
    @IBOutlet weak var takePhotoButton: UIButton!
    @IBOutlet weak var geminiSwitch: UISwitch!
    
    let openAIKey = "openAIKey"
    let geminiKey = "geminiKey"
    var useGemini = false  // true to use Gemini Pro Vision. false to use GPT4V
    let prompt =
    "You act as an independent referee for Chinese military chess (Luzhanqi). Rank comparison: Field Marshal > General > Major General > Brigadier > Colonel > Major > Captain > Lieutenant > Engineer. Take a deep breath and work on this step by step. First you examine the photo carefully and identify their ranks and colors. Compare them and announce the outcome by referring to their color, avoiding mention of position such as left/right. Remember, no talking about the ranks, never! No explanations. There is no other color but a black piece and a red piece."
    
    let captureSession = AVCaptureSession()
    var photoOutput = AVCapturePhotoOutput()
    var audioPlayer: AVAudioPlayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        geminiSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        
        updateButtonAndTakePhotoButtonState()
        setupCameraSession()
    }
    
    func callAPIAndPlayMP3(_ text: String) {
        let urlString = "https://api.openai.com/v1/audio/speech"
        guard let url = URL(string: urlString) else { return }
        
        guard let key = UserDefaults.standard.string(forKey: openAIKey) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": "alloy",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        let session = URLSession.shared
        session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            self.playMP3FromData(data)
        }.resume()
    }
    
    func playMP3FromData(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to play audio: \(error.localizedDescription)")
        }
    }
    
    @IBAction func switchChanged(_ sender: UISwitch) {
        useGemini = sender.isOn
    }
    
    @IBAction func apiKeyButtonTapped(_ sender: UIButton) {
        // this func handles both key buttons tapped
        var openAIKeyButton = true
        if sender.tag == 2 { openAIKeyButton = false }
        
        if UserDefaults.standard.string(forKey: openAIKeyButton ? openAIKey : geminiKey) != nil {
            UserDefaults.standard.removeObject(forKey: openAIKeyButton ? openAIKey : geminiKey)
            updateButtonAndTakePhotoButtonState()
        } else {
            let alert = UIAlertController(title: "Enter API Key", message: nil, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.placeholder = (openAIKeyButton ? "OpenAI" : "Gemini") + " API Key"
            }
            let submitAction = UIAlertAction(title: "Submit", style: .default) { [unowned alert] _ in
                let textField = alert.textFields![0]
                if let apiKey = textField.text, !apiKey.isEmpty {
                    UserDefaults.standard.set(
                        apiKey, forKey: (openAIKeyButton ? self.openAIKey : self.geminiKey))
                    self.updateButtonAndTakePhotoButtonState()
                }
            }
            alert.addAction(submitAction)
            present(alert, animated: true)
        }
    }
    
    func updateButtonAndTakePhotoButtonState() {
        openAIKeyButton.setTitle(
            UserDefaults.standard.string(forKey: openAIKey) != nil
            ? "Clear OpenAI Key" : "Enter OpenAI Key", for: .normal)
        geminiKeyButton.setTitle(
            UserDefaults.standard.string(forKey: geminiKey) != nil
            ? "Clear Gemini Key" : "Enter Gemini Key", for: .normal)
        // Whisper needs OpenAI key so required
        takePhotoButton.isEnabled = UserDefaults.standard.string(forKey: openAIKey) != nil
    }
    
    func setupCameraSession() {
        captureSession.beginConfiguration()
        
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        guard let backCamera = deviceDiscoverySession.devices.first,
              let input = try? AVCaptureDeviceInput(device: backCamera)
        else {
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
    
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData),
           let croppedImage = cropToSquare(image: image)
        {
            // Resize the image to 512x512 pixels
            let resizedImage = resizeImage(
                image: croppedImage, targetSize: CGSize(width: 512, height: 512))
            imageView.image = resizedImage
            
            // begin to referee
            if useGemini {
                Task {
                    let response = try await GeminiReferee(image)
                    print(response)
                    //                        self.callAPIAndPlayMP3(response)
                }
            } else {
                OpenAIReferee(image) { result in
                    switch result {
                    case .success(let response):
                        print(response)
                        //                        self.callAPIAndPlayMP3(response)
                    case .failure(let error):
                        print("Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func OpenAIReferee(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        if let base64String = image.jpegData(compressionQuality: 1.0)?.base64EncodedString() {
            callGPT4VisionAPI(with: base64String) { result in
                switch result {
                case .success(let response):
                    completion(.success(response))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func GeminiReferee(_ image: UIImage) async throws -> String {
        guard let key = UserDefaults.standard.string(forKey: geminiKey) else { return "" }
        let config = GenerationConfig(
            maxOutputTokens: 1000
        )
        let model = GenerativeModel(name: "gemini-pro-vision", apiKey: key, generationConfig: config)
        
        let response = try await model.generateContent(prompt, image)
        if let text = response.text {
            return text
        } else {
            return ""
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
        
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: cropSize, height: cropSize), false, image.scale)
        image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        let croppedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return croppedImage
    }
    
    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let newSize =
        widthRatio > heightRatio
        ? CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        : CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
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
    
    func callGPT4VisionAPI(
        with imageBase64: String, completion: @escaping (Result<String, Error>) -> Void
    ) {
        if let key = UserDefaults.standard.string(forKey: openAIKey) {
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            
            let systemMessageContent = prompt
            
            let payload: [String: Any] = [
                "model": "gpt-4-vision-preview",
                "messages": [
                    ["role": "system", "content": systemMessageContent],
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)", "detail": "low"],
                            ]
                        ],
                    ],
                ],
                "max_tokens": 1000,
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                completion(.failure(error))
                return
            }
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(
                        .failure(
                            NSError(
                                domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String
                    {
                        completion(.success(content))
                    } else {
                        completion(
                            .failure(
                                NSError(
                                    domain: "", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
            
            task.resume()
        }
    }
}
