            // Find highest point in group to place text above it
            let highestY = group.max { $0.y < $1.y }?.y ?? center.y
            let textPosition = simd_float3(center.x, highestY + 0.15, center.z)
            
            // Create anchor for text entity
            let textAnchor = AnchorEntity(world: textPosition)
            
            // Fix text orientation - rotate text to face correctly
            textEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            
            // Add entities to hierarchy
            textAnchor.addChild(backgroundEntity)
            textAnchor.addChild(textEntity)
            rootAnchor.addChild(textAnchor)
            
            // Add look-at constraint to make text always face the camera
            if let arView = self.arView {
                let cameraAnchor = AnchorEntity(.camera)
                arView.scene.addAnchor(cameraAnchor)
                
                // Update text orientation in each frame to face camera
                arView.scene.subscribe(to: SceneEvents.Update.self) { [weak textAnchor] event in
                    guard let textAnchor = textAnchor else { return }
                    
                    // Get camera position
                    let cameraTransform = arView.cameraTransform
                    let cameraPosition = cameraTransform.translation
                    
                    // Calculate direction from text to camera
                    let textPosition = textAnchor.position(relativeTo: nil)
                    let direction = normalize(cameraPosition - textPosition)
                    
                    // Make text face the camera
                    textAnchor.look(at: cameraPosition, from: textPosition, relativeTo: nil)
                }
            }
            
            print("Added text label for object group #\(index+1) with \(group.count) vertices at \(center)") 