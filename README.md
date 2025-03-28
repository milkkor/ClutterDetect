# ClutterDetect app

## Overview

This app is a tool for scanning indoor spaces using Apple's RoomPlan and ARKit technologies. It can:

1. Scan and identify walls, floors, doors, and windows in indoor environments.
2. Recognize furniture and objects like tables and chairs.
3. **Detect unidentified objects** on the floor in real-time.
4. Generate exportable 3D models in USDZ format.

This app demonstrates how to use the latest AR technology to digitize physical spaces, providing a foundation for interior design, furniture arrangement, and virtual space modeling.

## Technical Foundation

### Core Technologies

1. **RoomPlan API**
   - Introduced by Apple in iOS 16.
   - Designed for scanning and modeling indoor spaces.
   - Capable of recognizing common structural elements and furniture.

2. **ARKit**
   - Apple's augmented reality framework.
   - Provides spatial tracking, environment understanding, and scene reconstruction.
   - This app uses ARKit's mesh reconstruction feature.

3. **RealityKit**
   - Used for rendering 3D content and enhancing AR experiences.
   - Manages 3D objects and environments.

## Detailed Features

### 1. Indoor Space Scanning

The app uses the device's camera to scan the surrounding environment and create a 3D model of the indoor space. During scanning, the app identifies:
- Structural elements: walls, floors, doors, windows, and ceilings.
- Furniture items: tables, chairs, sofas, etc.

After scanning, users receive a parametric room model with all identified elements and dimensions.

### 2. Floor Object Detection

A standout feature is the intelligent detection of objects on the floor that RoomPlan doesn't automatically recognize:
- Uses ARKit's mesh classification technology.
- Analyzes unclassified mesh surfaces.
- Filters based on object height and position.
- Groups and labels areas that might be objects on the floor.

This allows the app to detect small items or uncommon furniture, enhancing scan completeness.

### 3. Visual Feedback

The app provides rich visual feedback:
- A semi-transparent overlay shows structures and objects identified by RoomPlan.
- Adds 3D labels to detected floor objects.
- A label at the top of the screen shows the number of detected objects.
- Regularly outputs scan status and mesh classification statistics.

### 4. Data Export

After scanning, users can:
- Export a parametric 3D model in USDZ format.
- Save room data in JSON format.
- Share results with other apps using the system's sharing feature.

## Implementation Details


### Key Technical Points

1. **Shared ARSession**
   - The app creates a shared `ARSession` for RoomPlan and ARKit.
   - This allows both systems to work simultaneously and share tracking data.

2. **Multi-layer Visual Overlay**
   - `ARView` serves as the base view displaying AR content.
   - `RoomCaptureView` is the top layer showing the RoomPlan model.
   - Adjusting transparency allows both effects to be displayed simultaneously.

3. **Floor Object Detection Algorithm**
   ```
   1. Obtain ARKit mesh data and extract unclassified surfaces.
   2. Calculate the height of each vertex based on the floor plane.
   3. Filter surfaces within a specified height range.
   4. Perform simple spatial clustering to identify objects.
   5. Create visual markers for each detected object.
   ```

4. **Performance Optimization**
   - Uses background threads for time-consuming detection calculations.
   - Limits the number of processed surfaces to avoid performance issues.
   - Sets detection intervals to reduce computation frequency.

## How to Use

1. **Start Scanning**
   - The app automatically starts scanning when launched.
   - Slowly move the device around the room.
   - Ensure good lighting and stable movement.

2. **Scanning Process**
   - The system automatically identifies walls, floors, doors, windows, and furniture.
   - The software detects unidentified objects on the floor.
   - The screen displays real-time scanning progress and detection results.

3. **Complete Scanning**
   - Press the "Done" button to end scanning.
   - The system processes the final data (may take a few seconds).
   - Displays the final model results.

4. **Export Results**
   - Press the "Export" button to save the model.
   - Choose sharing options to send the model to other apps.
   - The model can be viewed in apps that support the USDZ format.

## System Requirements

- Requires iOS 16.0 or later on iPhones or iPad Pros with LiDAR.