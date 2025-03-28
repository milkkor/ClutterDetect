import UIKit
import RoomPlan
import ARKit
import RealityKit

class FloorObjectDetector {
    // Reference to ARView
    private weak var arView: ARView?
    
    // Current room data from RoomPlan
    private var currentRoomData: CapturedRoom?
    
    // Visualization properties
    private var highlightedMeshAnchor: AnchorEntity?
    
    // Detection timing control
    private var lastObjectDetectionTime = Date()
    private let objectDetectionInterval: TimeInterval = 2.0 // Check every 2 seconds
    
    // Height parameters for object detection
    private let minObjectHeight: Float = 0.02  // 2cm
    private let maxObjectHeight: Float = 0.40  // 40cm
    
    // Add these properties to the FloorObjectDetector class
    private var visualMarkerEntities: [UUID: AnchorEntity] = [:]
    private var meshMarkers: [ModelEntity] = []
    private var meshMarkerAnchor: AnchorEntity?
    private var lowUnclassifiedMeshes: [[simd_float3]] = [] // Store point clouds of unclassified objects on the floor
    private let clusteringDistance: Float = 0.05 // 5cm clustering distance for point groups
    
    // Add a property to track the 2D label
    private var screenLabel: UILabel?
    
    // Initialize with ARView
    init(arView: ARView?) {
        self.arView = arView
    }
    
    // Update the current room data
    func updateRoomData(_ roomData: CapturedRoom) {
        self.currentRoomData = roomData
    }
    
    // Process mesh classifications
    func processClassificationsFromMesh(_ meshAnchor: ARMeshAnchor) {
        // Get mesh face information
        let faces = meshAnchor.geometry.faces
        
        // Ensure mesh has faces
        guard faces.count > 0 else { return }
        
        // Collect unclassified face information
        var unclassifiedFaces: [(faceIndex: Int, vertices: [simd_float3])] = []
        
        // Iterate through all faces, get their classification
        for i in 0..<faces.count {
            let classification = meshAnchor.geometry.classificationOf(faceWithIndex: i)
            
            // If it's an unclassified face, collect its vertices and face index
            if classification == .none {
                // Get the vertex indices for the face
                let vertexIndices = faces[Int(i)]
                
                // Collect all vertices transformed to world coordinates
                var worldVertices: [simd_float3] = []
                for index in vertexIndices {
                    let vertex = getVertex(from: meshAnchor.geometry, at: Int(index))
                    let worldVertex = transformPoint(vertex, with: meshAnchor.transform)
                    worldVertices.append(worldVertex)
                }
                
                // Store face index and corresponding vertices
                unclassifiedFaces.append((faceIndex: Int(i), vertices: worldVertices))
            }
        }
        
        // Check for unclassified faces on the floor
        let now = Date()
        if !unclassifiedFaces.isEmpty && 
            now.timeIntervalSince(lastObjectDetectionTime) >= objectDetectionInterval, 
           let currentRoom = currentRoomData, 
           !currentRoom.floors.isEmpty {
            
            lastObjectDetectionTime = now
            
            // Process detection in background thread to avoid blocking main thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Filter faces with height criteria
                let validFaces = self.filterFacesWithValidHeight(
                    faces: unclassifiedFaces,
                    floorTransform: currentRoom.floors[0].transform
                )
                
                if !validFaces.isEmpty {
                    DispatchQueue.main.async {
                        self.renderValidFaces(meshAnchor: meshAnchor, validFaces: validFaces)
                        print("Found \(validFaces.count) faces meeting height criteria")
                    }
                }
            }
        }
    }
    
    // Get vertex from mesh geometry
    private func getVertex(from geometry: ARMeshGeometry, at index: Int) -> simd_float3 {
        let vertexPointer = geometry.vertices.buffer.contents().advanced(by: geometry.vertices.offset + (geometry.vertices.stride * index))
        let vertex = vertexPointer.assumingMemoryBound(to: (Float, Float, Float).self).pointee
        return simd_float3(vertex.0, vertex.1, vertex.2)
    }
    
    // Transform point from local to world coordinate system
    private func transformPoint(_ point: simd_float3, with transform: simd_float4x4) -> simd_float3 {
        let worldPoint = transform * simd_float4(point.x, point.y, point.z, 1.0)
        return simd_float3(worldPoint.x, worldPoint.y, worldPoint.z)
    }
    
    // Filter faces where all vertices are within valid height range and not inside recognized objects
    private func filterFacesWithValidHeight(faces: [(faceIndex: Int, vertices: [simd_float3])], floorTransform: simd_float4x4) -> [Int] {
        // Calculate floor height and normal vector
        let floorNormal = simd_float3(floorTransform.columns.1.x, floorTransform.columns.1.y, floorTransform.columns.1.z)
        let floorPosition = simd_float3(floorTransform.columns.3.x, floorTransform.columns.3.y, floorTransform.columns.3.z)
        
        // Filter faces where all vertices are within valid height range
        var validFaceIndices: [Int] = []
        
        // Get current room objects
        let roomObjects = currentRoomData?.objects ?? []
        
        for face in faces {
            // Check if all vertices of this face are within height range
            var allVerticesValid = true
            
            for vertex in face.vertices {
                let height = heightAboveFloor(vertex, floorPosition: floorPosition, floorNormal: floorNormal)
                
                // Check height condition
                if height < minObjectHeight || height > maxObjectHeight {
                    allVerticesValid = false
                    break
                }
                
                // Check if vertex is inside any recognized object
                if isPointInsideAnyObject(vertex, objects: roomObjects) {
                    allVerticesValid = false
                    break
                }
            }
            
            // Only add face index to valid list when all vertices meet criteria
            if allVerticesValid && !face.vertices.isEmpty {
                validFaceIndices.append(face.faceIndex)
            }
        }
        
        print("Filtering results: \(faces.count) unclassified faces, \(validFaceIndices.count) faces have all vertices within height range and not inside recognized objects")
        
        return validFaceIndices
    }
    
    // Check if point is inside any recognized object
    private func isPointInsideAnyObject(_ point: simd_float3, objects: [CapturedRoom.Object]) -> Bool {
        for object in objects {
            // Get object center position and dimensions
            let objectPosition = simd_float3(
                object.transform.columns.3.x,
                object.transform.columns.3.y,
                object.transform.columns.3.z
            )
            
            // Get object local coordinate system axes
            let xAxis = simd_float3(object.transform.columns.0.x, object.transform.columns.0.y, object.transform.columns.0.z)
            let yAxis = simd_float3(object.transform.columns.1.x, object.transform.columns.1.y, object.transform.columns.1.z)
            let zAxis = simd_float3(object.transform.columns.2.x, object.transform.columns.2.y, object.transform.columns.2.z)
            
            // Half sizes of the object
            let halfSizes = object.dimensions / 2
            
            // Transform point to object's local coordinate system
            let localPoint = objectLocalPosition(point, objectPosition: objectPosition, 
                                              xAxis: xAxis, yAxis: yAxis, zAxis: zAxis)
            
            // Check if point is within object's bounding box
            if abs(localPoint.x) <= halfSizes.x &&
               abs(localPoint.y) <= halfSizes.y &&
               abs(localPoint.z) <= halfSizes.z {
                return true
            }
        }
        
        return false
    }
    
    // Transform point to object's local coordinate system
    private func objectLocalPosition(_ point: simd_float3, objectPosition: simd_float3, 
                                   xAxis: simd_float3, yAxis: simd_float3, zAxis: simd_float3) -> simd_float3 {
        // Calculate vector from object center to point
        let relativePoint = point - objectPosition
        
        // Project onto object's coordinate axes
        let localX = simd_dot(relativePoint, normalize(xAxis))
        let localY = simd_dot(relativePoint, normalize(yAxis))
        let localZ = simd_dot(relativePoint, normalize(zAxis))
        
        return simd_float3(localX, localY, localZ)
    }
    
    // Calculate height of a point above the floor
    private func heightAboveFloor(_ point: simd_float3, floorPosition: simd_float3, floorNormal: simd_float3) -> Float {
        // Calculate floor plane equation: dot(normal, X - position) = 0, where X is any point on the plane
        // Distance from point to plane is |dot(normal, point - position)| / |normal|
        // Since normal is usually a unit vector, denominator is 1
        let vectorToPoint = point - floorPosition
        return abs(simd_dot(vectorToPoint, floorNormal))
    }
    
    // Group valid faces and display 3D text labels
    private func renderValidFaces(meshAnchor: ARMeshAnchor, validFaces: [Int]) {
        guard let arView = self.arView else { return }
        
        // Clear previous highlighted mesh and text labels
        if let existingAnchor = highlightedMeshAnchor {
            arView.scene.removeAnchor(existingAnchor)
            highlightedMeshAnchor = nil
        }
        
        // Return if no valid faces
        if validFaces.isEmpty {
            print("No qualifying faces found")
            // Hide the screen label if no objects detected
            hideScreenLabel()
            return
        }
        
        print("Found \(validFaces.count) qualifying faces, starting grouping")
        
        // Limit number of processed faces to avoid performance issues
        let maxFaces = min(validFaces.count, 1000)
        let facesToProcess = validFaces.prefix(maxFaces)
        
        // Collect all vertices from valid faces
        var allVertices: [simd_float3] = []
        
        for faceIndex in facesToProcess {
            // Get vertex indices for the face
            let vertexIndices = meshAnchor.geometry.faces[faceIndex]
            
            // Collect and transform vertices to world coordinates
            for index in vertexIndices {
                let vertex = getVertex(from: meshAnchor.geometry, at: Int(index))
                let worldVertex = transformPoint(vertex, with: meshAnchor.transform)
                allVertices.append(worldVertex)
            }
        }
        
        // Group vertices that are close to each other
        let clusteringDistance: Float = 0.1 // 10cm clustering threshold
        var vertexGroups: [[simd_float3]] = []
        
        // Simple clustering algorithm
        for vertex in allVertices {
            var addedToExistingGroup = false
            
            // Try to add to existing group
            for i in 0..<vertexGroups.count {
                // Check if vertex is close to any vertex in the group
                for groupVertex in vertexGroups[i] {
                    if distance(vertex, groupVertex) <= clusteringDistance {
                        vertexGroups[i].append(vertex)
                        addedToExistingGroup = true
                        break
                    }
                }
                if addedToExistingGroup { break }
            }
            
            // If not added to any existing group, create a new group
            if !addedToExistingGroup {
                vertexGroups.append([vertex])
            }
        }
        
        // Merge overlapping groups
        var i = 0
        while i < vertexGroups.count {
            var j = i + 1
            while j < vertexGroups.count {
                // Check if groups overlap
                var groupsOverlap = false
                
                for vertexA in vertexGroups[i] {
                    for vertexB in vertexGroups[j] {
                        if distance(vertexA, vertexB) <= clusteringDistance {
                            groupsOverlap = true
                            break
                        }
                    }
                    if groupsOverlap { break }
                }
                
                // If groups overlap, merge them
                if groupsOverlap {
                    vertexGroups[i].append(contentsOf: vertexGroups[j])
                    vertexGroups.remove(at: j)
                } else {
                    j += 1
                }
            }
            i += 1
        }
        
        // Filter out small groups (less than 10 vertices)
        let filteredGroups = vertexGroups.filter { $0.count >= 10 }
        
        print("Grouped vertices into \(filteredGroups.count) object clusters")
        
        if filteredGroups.isEmpty {
            // Hide the screen label if no groups found
            hideScreenLabel()
        } else {
            // Show the screen label with the count of detected objects
            showScreenLabel(count: filteredGroups.count)
        }
        
        // Create an anchor to hold all text entities
        let rootAnchor = AnchorEntity()
        
        // Create text labels for each group
        for (index, group) in filteredGroups.enumerated() {
            // Calculate center of the group
            let center = group.reduce(simd_float3.zero) { $0 + $1 } / Float(group.count)
            
            // Find highest point in group to place marker above it
            let highestY = group.max { $0.y < $1.y }?.y ?? center.y
            let markerPosition = simd_float3(center.x, highestY + 0.10, center.z)
            
            // Create anchor for sphere marker
            let markerAnchor = AnchorEntity(world: markerPosition)
            
            // Create a red sphere marker
            let sphereMesh = MeshResource.generateSphere(radius: 0.05)
            let sphereMaterial = SimpleMaterial(color: .red, isMetallic: false)
            let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
            
            // Add sphere to hierarchy
            markerAnchor.addChild(sphereEntity)
            rootAnchor.addChild(markerAnchor)
            
            print("Added sphere marker for object group #\(index+1) with \(group.count) vertices at \(center)")
        }
        
        // Add all entities to scene
        arView.scene.addAnchor(rootAnchor)
        highlightedMeshAnchor = rootAnchor
        
        print("Displayed labels for \(filteredGroups.count) detected objects on the floor")
    }
    
    // Show 2D screen label with object count
    private func showScreenLabel(count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let arView = self.arView else { return }
            
            // Create label if it doesn't exist
            if self.screenLabel == nil {
                let label = UILabel()
                label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                label.textColor = .yellow
                label.textAlignment = .center
                label.layer.cornerRadius = 10
                label.layer.masksToBounds = true
                label.font = UIFont.boldSystemFont(ofSize: 24)
                label.numberOfLines = 0
                
                // Add to AR view
                arView.addSubview(label)
                
                // Set constraints
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.topAnchor, constant: 20),
                    label.leadingAnchor.constraint(equalTo: arView.leadingAnchor, constant: 20),
                    label.trailingAnchor.constraint(equalTo: arView.trailingAnchor, constant: -20),
                ])
                
                self.screenLabel = label
            }
            
            // Update text
            let labelText = count == 1 ? 
                "Found 1 item on surface" : 
                "Found \(count) items on surface"
            
            self.screenLabel?.text = labelText
            self.screenLabel?.isHidden = false
            
            // Animate label appearance
            self.screenLabel?.alpha = 0
            UIView.animate(withDuration: 0.5) {
                self.screenLabel?.alpha = 1
            }
        }
    }
    
    // Hide screen label
    private func hideScreenLabel() {
        DispatchQueue.main.async { [weak self] in
            guard let label = self?.screenLabel else { return }
            
            UIView.animate(withDuration: 0.5, animations: {
                label.alpha = 0
            }, completion: { _ in
                label.isHidden = true
            })
        }
    }
    
    // Helper function to calculate distance between two points
    private func distance(_ a: simd_float3, _ b: simd_float3) -> Float {
        let diff = a - b
        return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
    }
    
    // Add this method to clear visual markers
    public func clearVisualMarkers() {
        DispatchQueue.main.async {
            for (_, entity) in self.visualMarkerEntities {
                self.arView?.scene.removeAnchor(entity)
            }
            self.visualMarkerEntities.removeAll()
            
            if let meshMarkerAnchor = self.meshMarkerAnchor {
                self.arView?.scene.removeAnchor(meshMarkerAnchor)
                self.meshMarkerAnchor = nil
            }
            self.meshMarkers.removeAll()
            
            // Also hide the screen label
            self.hideScreenLabel()
        }
    }
    
    // Add visual marker for detected objects
    public func addVisualMarker(forObjectAt position: simd_float3, withSize size: simd_float3, index: Int) {
        guard let arView = self.arView else { return }
        
        DispatchQueue.main.async {
            // Create a unique identifier for the object
            let objectID = UUID()
            
            // Create anchor entity at the center of the object
            let anchorEntity = AnchorEntity(world: .init(position))
            
            // Create box entity
            let boxSize = max(size.x, 0.05) * max(size.z, 0.05) * max(size.y, 0.05)
            let boxScale = pow(boxSize, 1/3) // Cubic root to make box size balanced
            
            // Create frame model representing the detected object boundary
            let boxMesh = MeshResource.generateBox(size: 1)
            var material = SimpleMaterial()
            material.color = .init(tint: .red.withAlphaComponent(0.3), texture: nil)
            
            let boxEntity = ModelEntity(mesh: boxMesh, materials: [material])
            boxEntity.scale = .init(repeating: boxScale)
            
            // Add text label showing object number
            let textMesh = MeshResource.generateText("Object #\(index + 1)",
                                                   extrusionDepth: 0.01,
                                                   font: .systemFont(ofSize: 0.2),
                                                   containerFrame: .zero,
                                                   alignment: .center,
                                                   lineBreakMode: .byTruncatingTail)
            
            let textMaterial = SimpleMaterial(color: .yellow, isMetallic: false)
            let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
            
            // Adjust text size and position
            textEntity.scale = .init(repeating: 0.05)
            textEntity.position = SIMD3<Float>(0, boxScale/2 + 0.05, 0)  // Place above the object
            
            // Assemble entity hierarchy
            anchorEntity.addChild(boxEntity)
            anchorEntity.addChild(textEntity)
            
            // Add marker to scene and store reference
            arView.scene.addAnchor(anchorEntity)
            self.visualMarkerEntities[objectID] = anchorEntity
        }
    }
}

// SIMD3 Extension
extension SIMD3 where Scalar == Float {
    static var zero: SIMD3<Float> {
        return SIMD3<Float>(0, 0, 0)
    }
}
