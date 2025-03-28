/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The sample app's main view controller that manages the scanning process.
*/

import UIKit
import RoomPlan
import ARKit
import RealityKit
import Combine

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, ARSessionDelegate {
    
    // MARK: - UI Outlets
    
    @IBOutlet var exportButton: UIButton?
    @IBOutlet var doneButton: UIBarButtonItem?
    @IBOutlet var cancelButton: UIBarButtonItem?
    @IBOutlet var activityIndicator: UIActivityIndicatorView?
    
    // MARK: - Scanning Properties
    
    private var isScanning: Bool = false
    private var finalResults: CapturedRoom?
    private var currentRoomData: CapturedRoom?
    
    // MARK: - RoomPlan Properties
    
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSession: RoomCaptureSession!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    
    // MARK: - ARKit Properties
    
    private var sharedARSession: ARSession!
    private var arView: ARView?
    
    // MARK: - Tracking Properties
    
    // Track known object and surface IDs to avoid duplicate output
    private var knownObjectIDs: Set<UUID> = []
    private var knownSurfaceIDs: Set<UUID> = []
    
    // Properties for tracking object classification statistics
    private var meshClassificationCounts: [ARMeshClassification: Int] = [:]
    private var lastClassificationReport = Date()
    private let reportInterval: TimeInterval = 3.0 // Report classifications every 3 seconds
    
    // MARK: - Object Detection
    
    private var floorObjectDetector: FloorObjectDetector?
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up shared ARSession and view layers
        setupSharedARSession()
        
        activityIndicator?.stopAnimating()
        
        // Add timer to periodically check scanning status (every 5 seconds)
        Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(checkScanningStatus), userInfo: nil, repeats: true)
        
        // Initialize object detector
        floorObjectDetector = FloorObjectDetector(arView: arView)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession()
    }
    
    // MARK: - AR Session Setup
    
    private func setupSharedARSession() {
        // Create shared ARSession instance
        sharedARSession = ARSession()
        sharedARSession.delegate = self
        
        // Check if device supports scene reconstruction
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            print("This device does not support scene mesh reconstruction")
            return
        }
        
        // Create ARView as the base view
        arView = ARView(frame: view.bounds, cameraMode: .ar, automaticallyConfigureSession: false)
        arView?.session = sharedARSession
        
        // Configure ARKit - use mesh reconstruction with classification
        arView?.automaticallyConfigureSession = false
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification  // Use mesh with classification
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal, .vertical]  // Enable plane detection
        
        arView?.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
        arView?.environment.sceneUnderstanding.options = []
        arView?.environment.sceneUnderstanding.options.insert(.occlusion)
        arView?.environment.sceneUnderstanding.options.insert(.physics)
        
        view.insertSubview(arView!, at: 0)
        
        // Run shared ARSession
        sharedARSession.run(config)
        print("Started shared ARSession mesh scanning")
        
        // Create RoomCaptureView using shared ARSession
        roomCaptureView = RoomCaptureView(frame: view.bounds, arSession: sharedARSession)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        roomCaptureView.backgroundColor = .clear  // Set transparent background
        roomCaptureView.alpha = 0.7  // Set appropriate transparency to see both effects
        roomCaptureView.isModelEnabled = true  // Enable RoomPlan 3D model preview
        
        view.insertSubview(roomCaptureView, aboveSubview: arView!)
        
        // Save RoomCaptureSession reference for later use
        roomCaptureSession = roomCaptureView.captureSession
        
        print("Set up RoomCaptureView with shared ARSession, both mesh and RoomPlan models will display simultaneously")
    }
    
    // MARK: - Session Management
    
    private func startSession() {
        isScanning = true
        currentRoomData = nil
        
        // Clear collections of known objects and surfaces
        knownObjectIDs.removeAll()
        knownSurfaceIDs.removeAll()
        
        // Start RoomCaptureSession
        roomCaptureSession.run(configuration: roomCaptureSessionConfig)
        print("Started RoomCaptureSession (using shared ARSession)")
        
        setActiveNavBar()
    }
    
    private func stopSession() {
        isScanning = false
        
        // Stop RoomCaptureSession
        roomCaptureSession.stop()
        
        // Stop shared ARSession
        sharedARSession.pause()
        print("Stopped RoomCaptureSession and shared ARSession")
        
        // Keep RoomCaptureView transparency to maintain visual effect
        
        setCompleteNavBar()
    }
    
    // MARK: - UI Management
    
    private func setActiveNavBar() {
        UIView.animate(withDuration: 1.0, animations: {
            self.cancelButton?.tintColor = .white
            self.doneButton?.tintColor = .white
            self.exportButton?.alpha = 0.0
        }, completion: { complete in
            self.exportButton?.isHidden = true
        })
    }
    
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.cancelButton?.tintColor = .systemBlue
            self.doneButton?.tintColor = .systemBlue
            self.exportButton?.alpha = 1.0
        }
    }
    
    // MARK: - Status Monitoring
    
    @objc private func checkScanningStatus() {
        print("=== Scanning Status Report ===")
        print("RoomPlan scanning active: \(isScanning)")
        
        if let finalResults = finalResults {
            print("RoomPlan results - Floors: \(finalResults.floors.count), Walls: \(finalResults.walls.count), Objects: \(finalResults.objects.count)")
        }
        print("===========================")
    }
    
    private func reportClassificationStatistics() {
        guard !meshClassificationCounts.isEmpty else { return }
        
        print("\n=== ARKit Mesh Classification Statistics ===")
        
        // Sort classifications for ordered display
        let sortedClassifications = meshClassificationCounts.sorted { $0.value > $1.value }
        
        for (classification, count) in sortedClassifications {
            let name = getClassificationName(classification)
            print("  \(name): \(count) surfaces")
        }
        
        print("=========================================\n")
    }
    
    private func getClassificationName(_ classification: ARMeshClassification) -> String {
        switch classification {
        case .ceiling:        return "Ceiling"
        case .door:           return "Door"
        case .floor:          return "Floor"
        case .seat:           return "Seat"
        case .table:          return "Table"
        case .wall:           return "Wall"
        case .window:         return "Window"
        case .none:           return "Unclassified"
        @unknown default:     return "Unknown Type (\(classification.rawValue))"
        }
    }
    
    // MARK: - Button Actions
    
    @IBAction func doneScanning(_ sender: UIBarButtonItem) {
        if isScanning { 
            // User pressed done button, stop scanning
            stopSession()
            
            // Show processing indicator
            self.exportButton?.isEnabled = false
            self.activityIndicator?.startAnimating()
            
            print("User pressed done, waiting for processing results")
        } else { 
            cancelScanning(sender) 
        }
    }

    @IBAction func cancelScanning(_ sender: UIBarButtonItem) {
        navigationController?.dismiss(animated: true)
    }
    
    // Export the USDZ output by specifying the `.parametric` export option.
    // Alternatively, `.mesh` exports a nonparametric file and `.all`
    // exports both in a single USDZ.
    @IBAction func exportResults(_ sender: UIButton) {
        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
        let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
        let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")
        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(finalResults)
            try jsonData.write(to: capturedRoomURL)
            try finalResults?.export(to: destinationURL, exportOptions: .parametric)
            
            let activityVC = UIActivityViewController(activityItems: [destinationFolderURL], applicationActivities: nil)
            activityVC.modalPresentationStyle = .popover
            
            present(activityVC, animated: true, completion: nil)
            if let popOver = activityVC.popoverPresentationController {
                popOver.sourceView = self.exportButton
            }
        } catch {
            print("Error = \(error)")
        }
    }
    
    // MARK: - RoomCaptureViewDelegate Methods
    
    // Decide to post-process and show the final results.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }
    
    // Access the final post-processed results.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        self.exportButton?.isEnabled = true
        self.activityIndicator?.stopAnimating()

        roomCaptureView.alpha = 1.0 
        print("RoomPlan scan completed, updated visualization display, showing final results")
    }
    
    // MARK: - ARSessionDelegate Methods
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                floorObjectDetector?.processClassificationsFromMesh(meshAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                floorObjectDetector?.processClassificationsFromMesh(meshAnchor)
            }
        }
        
        // Periodically report classification statistics
        let now = Date()
        if now.timeIntervalSince(lastClassificationReport) >= reportInterval {
            lastClassificationReport = now
            reportClassificationStatistics()
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Empty method retained for future use
    }
    
    // MARK: - RoomCaptureSessionDelegate Methods
    
    func captureSession(_ session: RoomCaptureSession, didUpdate capturedRoom: CapturedRoom) {
        // Update current scan results
        currentRoomData = capturedRoom
        
        // Update detector
        floorObjectDetector?.updateRoomData(capturedRoom)
        
        // Output scan summary only
        print("Room scan update - Floors: \(capturedRoom.floors.count), Walls: \(capturedRoom.walls.count), Objects: \(capturedRoom.objects.count)")
    }
    
    func captureSession(_ session: RoomCaptureSession, didAdd capturedRoom: CapturedRoom) {
        // Update current scan results
        currentRoomData = capturedRoom
        
        // Update detector
        floorObjectDetector?.updateRoomData(capturedRoom)
        
        // Output basic information
        print("Room scan added elements - Floors: \(capturedRoom.floors.count), Walls: \(capturedRoom.walls.count), Objects: \(capturedRoom.objects.count)")
        
        // Check and output new objects
        for object in capturedRoom.objects {
            if !knownObjectIDs.contains(object.identifier) {
                knownObjectIDs.insert(object.identifier)
                print("\n[New Object] ID: \(object.identifier)")
            }
        }
    }
    
    func captureSession(_ session: RoomCaptureSession, didChange capturedRoom: CapturedRoom) {
        // Update current scan results
        currentRoomData = capturedRoom
        
        // Update detector
        floorObjectDetector?.updateRoomData(capturedRoom)
        
        // Output basic information only
        print("Room scan changes - Floors: \(capturedRoom.floors.count), Walls: \(capturedRoom.walls.count), Objects: \(capturedRoom.objects.count)")
    }
}

// Retain UUID extension, may be useful for other functionality
extension UUID: Hashable {
    // UUID already implements the Hashable protocol, this extension just confirms this
}

