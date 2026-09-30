# GlobeRenderer

A Swift Package that renders an interactive 3D globe with tiled map imagery using SceneKit. Supports pan, pinch-to-zoom, and momentum gestures out of the box, or lets the hosting app take full control of the camera.

![Platform: iOS 14+ | Mac Catalyst 14+](https://img.shields.io/badge/platform-iOS%2014%2B%20%7C%20Mac%20Catalyst%2014%2B-blue)

## Features

- Renders slippy map tiles on a 3D sphere with adaptive geometry subdivision
- Built-in pan, pinch-to-zoom, and scroll-wheel gestures with momentum
- Configurable tile imagery source (not limited to OpenStreetMap)
- Programmatic camera control via latitude, longitude, and zoom level
- Lock-north mode keeps geographic north at the top of the screen
- Optional download progress indicator and coordinate label
- Quadtree-based tile loading with frustum culling and level-of-detail
- Two-level tile cache (memory + disk)

## Installation

Add the package to your Xcode project:

1. **File > Add Package Dependencies...**
2. Enter the repository URL or add as a local package
3. Add the **GlobeRenderer** library to your target

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bryceco/GlobeRenderer.git", from: "1.0.0")
]
```

## Quick Start

```swift
import GlobeRenderer

let globe = GlobeView()
globe.frame = view.bounds
globe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
view.addSubview(globe)
```

That's it — you get an interactive globe with OpenStreetMap tiles.

## API

### GlobeView

The main view. Drop it into your view hierarchy and it handles everything.

```swift
public final class GlobeView: UIView {
    // Tile source — changeable at runtime, clears tiles and reloads
    var tileSource: TileSource

    // Camera position (lat/lon/zoom). Set to move programmatically.
    var camera: GlobeCamera { get set }

    // Keep geographic north at the top (default: true)
    var lockNorth: Bool

    // Install built-in gesture recognizers (default: true).
    // Set to false to control the camera yourself.
    var gesturesEnabled: Bool

    // Called on the main thread when gestures move the camera
    var onCameraChanged: ((GlobeCamera) -> Void)?

    // Animate camera to orient north upward
    func orientNorth(animated: Bool = true)

    // Toggle built-in UI overlays
    var showsDownloadIndicator: Bool  // spinner + download count
    var showsCoordinateLabel: Bool    // lat, lon, zoom label

    // Number of tile downloads in flight
    var pendingDownloadCount: Int { get }
}
```

### GlobeCamera

A simple value type for camera position.

```swift
public struct GlobeCamera: Equatable, Sendable {
    var latitude: Double   // degrees, -90 to 90
    var longitude: Double  // degrees, -180 to 180
    var zoom: Double       // 0 = whole earth, ~18 = street level
}
```

```swift
// Move to San Francisco at zoom 10
globe.camera = GlobeCamera(latitude: 37.7749, longitude: -122.4194, zoom: 10)
```

### TileSource

Conform to this protocol to provide custom tile imagery.

```swift
public protocol TileSource {
    func tileURL(for coordinate: TileCoordinate) -> URL
    var cacheDirectory: URL { get }
}
```

The package reads and writes tile PNGs at `{cacheDirectory}/{zoom}/{x}/{y}.png`. The host is responsible for creating the directory and cleaning it up when no longer needed.

### OpenStreetMapTileSource

A built-in tile source for OpenStreetMap. Used by default.

```swift
let osm = OpenStreetMapTileSource()
let globe = GlobeView(tileSource: osm)
```

### TileCoordinate

Identifies a single map tile.

```swift
public struct TileCoordinate: Hashable {
    let x: Int
    let y: Int
    let zoom: Int
}
```

## Custom Tile Source Example

```swift
struct MapboxTileSource: TileSource {
    let accessToken: String

    var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MapboxTiles", isDirectory: true)
    }

    func tileURL(for coordinate: TileCoordinate) -> URL {
        URL(string: "https://api.mapbox.com/v4/mapbox.satellite/\(coordinate.zoom)/\(coordinate.x)/\(coordinate.y).png?access_token=\(accessToken)")!
    }
}

globe.tileSource = MapboxTileSource(accessToken: "pk.your_token")
```

## Programmatic Camera Control

Disable built-in gestures and drive the camera yourself:

```swift
let globe = GlobeView()
globe.gesturesEnabled = false

// Move camera in response to your own UI
globe.camera = GlobeCamera(latitude: 48.8566, longitude: 2.3522, zoom: 12)
```

## Demo App

The repository includes a `GlobeDemo` Xcode project that shows basic usage — open `GlobeDemo.xcodeproj` and run on a device or simulator.
