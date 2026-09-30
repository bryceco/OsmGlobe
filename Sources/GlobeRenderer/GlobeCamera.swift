import Foundation
import simd

/// The camera position expressed as geographic coordinates.
public struct GlobeCamera: Equatable, Sendable {
    /// Latitude in degrees, -90 to 90.
    public var latitude: Double

    /// Longitude in degrees, -180 to 180.
    public var longitude: Double

    /// Zoom level, matching standard web map conventions.
    /// 0 = whole earth, ~18 = street level.
    public var zoom: Double

    public init(latitude: Double = 0, longitude: Double = 0, zoom: Double = 2) {
        self.latitude = latitude
        self.longitude = longitude
        self.zoom = zoom
    }
}

// MARK: - Internal conversion to/from quaternion + distance

extension GlobeCamera {
    static let minSurfaceDistance: Float = 0.00002
    static let maxSurfaceDistance: Float = 9.0

    /// Convert zoom to camera distance from sphere center.
    /// Derived from: zoom = log2(.pi / acos(1.0 / camDist))
    /// Therefore: camDist = 1.0 / cos(.pi / pow(2, zoom))
    var cameraDistance: Float {
        let d = Float(1.0 / cos(.pi / pow(2.0, zoom)))
        return max(1.0 + Self.minSurfaceDistance, min(1.0 + Self.maxSurfaceDistance, d))
    }

    /// Convert lat/lon to a quaternion that places the camera looking at (lat, lon)
    /// with north at the top of the screen.
    var cameraOrientation: simd_quatf {
        let latRad = Float(latitude * .pi / 180.0)
        let lonRad = Float(longitude * .pi / 180.0)

        // Camera identity is at (0,0,distance), looking toward origin along -Z.
        // geographicToCartesian: x = -cos(lat)*cos(lon), y = sin(lat), z = cos(lat)*sin(lon)
        // Camera position direction from origin for (0,0) is (0,0,1) in identity.
        // geographicToCartesian(0,0) = (-1, 0, 0), so identity maps (0,0,1) -> (-1,0,0)
        // We need rotation around Y by -(lon+pi) then around local X by -lat.
        let rotY = simd_quatf(angle: -(lonRad + .pi), axis: SIMD3<Float>(0, 1, 0))
        let right = rotY.act(SIMD3<Float>(1, 0, 0))
        let rotX = simd_quatf(angle: -latRad, axis: right)
        return simd_normalize(rotX * rotY)
    }

    /// Convert from quaternion + distance back to GlobeCamera.
    init(orientation: simd_quatf, distance: Float) {
        let position = orientation.act(SIMD3<Float>(0, 0, distance))
        let len = sqrt(position.x * position.x + position.y * position.y + position.z * position.z)

        self.latitude = Double(asin(position.y / len)) * 180.0 / .pi
        self.longitude = Double(atan2(position.z, -position.x)) * 180.0 / .pi
        self.zoom = max(0, Double(log2(.pi / acos(min(1.0, 1.0 / len)))))
    }
}
