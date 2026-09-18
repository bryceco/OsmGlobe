import SceneKit

enum GlobeMath {
    /// Convert geographic coordinates (radians) to a point on the unit sphere.
    /// Convention: Y is up (north pole), matching SceneKit's default.
    static func geographicToCartesian(lat: Double, lon: Double) -> SCNVector3 {
        let x = -cos(lat) * cos(lon)
        let y = sin(lat)
        let z = cos(lat) * sin(lon)
        return SCNVector3(Float(x), Float(y), Float(z))
    }

    /// Project a 3D world point to 2D screen coordinates.
    /// Projects a world-space point to screen coordinates.
    /// Returns `nil` if the point is behind the camera.
    static func projectToScreen(
        _ point: SCNVector3,
        viewProjection: SCNMatrix4,
        viewport: CGSize
    ) -> CGPoint? {
        let clip = multiplyMatrix(viewProjection, vector: SIMD4<Float>(point.x, point.y, point.z, 1.0))
        guard clip.w > 0.001 else { return nil }
        let ndc = CGPoint(
            x: CGFloat(clip.x / clip.w),
            y: CGFloat(clip.y / clip.w)
        )
        return CGPoint(
            x: (ndc.x + 1.0) * 0.5 * viewport.width,
            y: (1.0 - ndc.y) * 0.5 * viewport.height
        )
    }

    /// Multiply a 4x4 matrix by a 4-vector.
    private static func multiplyMatrix(_ m: SCNMatrix4, vector v: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4<Float>(
            m.m11 * v.x + m.m21 * v.y + m.m31 * v.z + m.m41 * v.w,
            m.m12 * v.x + m.m22 * v.y + m.m32 * v.z + m.m42 * v.w,
            m.m13 * v.x + m.m23 * v.y + m.m33 * v.z + m.m43 * v.w,
            m.m14 * v.x + m.m24 * v.y + m.m34 * v.z + m.m44 * v.w
        )
    }

    /// Distance between two 3D points.
    static func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /// Check if a point on the sphere is facing the camera (not on the back side).
    /// For a unit sphere, the surface normal at a point equals the point itself.
    static func isFacingCamera(tileCenter: SCNVector3, cameraPosition: SCNVector3) -> Bool {
        let toCam = SCNVector3(
            cameraPosition.x - tileCenter.x,
            cameraPosition.y - tileCenter.y,
            cameraPosition.z - tileCenter.z
        )
        let dot = tileCenter.x * toCam.x + tileCenter.y * toCam.y + tileCenter.z * toCam.z
        return dot > 0
    }

    /// Multiply two SCNMatrix4.
    static func multiplyMatrices(_ a: SCNMatrix4, _ b: SCNMatrix4) -> SCNMatrix4 {
        SCNMatrix4Mult(a, b)
    }
}
