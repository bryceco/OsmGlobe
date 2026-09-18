import SceneKit

struct TileCoordinate: Hashable, CustomStringConvertible {
    let x: Int
    let y: Int
    let zoom: Int

    var description: String { "\(zoom)/\(x)/\(y)" }

    /// The four children at zoom+1.
    var children: [TileCoordinate] {
        let cx = x * 2, cy = y * 2, cz = zoom + 1
        return [
            TileCoordinate(x: cx,     y: cy,     zoom: cz),
            TileCoordinate(x: cx + 1, y: cy,     zoom: cz),
            TileCoordinate(x: cx,     y: cy + 1, zoom: cz),
            TileCoordinate(x: cx + 1, y: cy + 1, zoom: cz),
        ]
    }

    /// Parent tile at zoom-1.
    var parent: TileCoordinate? {
        guard zoom > 0 else { return nil }
        return TileCoordinate(x: x / 2, y: y / 2, zoom: zoom - 1)
    }

    /// Geographic bounds (south-west to north-east) in radians.
    var geographicBounds: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        let n = Double(1 << zoom)
        let lonMin = Double(x) / n * 2.0 * .pi - .pi
        let lonMax = Double(x + 1) / n * 2.0 * .pi - .pi
        let latMax = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
        let latMin = atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n)))
        return (latMin, lonMin, latMax, lonMax)
    }

    /// Center of the tile in geographic radians.
    var centerLatLon: (lat: Double, lon: Double) {
        let b = geographicBounds
        return ((b.minLat + b.maxLat) / 2.0, (b.minLon + b.maxLon) / 2.0)
    }

    /// Center of the tile as a 3D point on the unit sphere.
    var centerOnSphere: SCNVector3 {
        let (lat, lon) = centerLatLon
        return GlobeMath.geographicToCartesian(lat: lat, lon: lon)
    }

    /// All tiles at a given zoom level.
    static func allTiles(atZoom zoom: Int) -> [TileCoordinate] {
        let count = 1 << zoom
        return (0..<count).flatMap { y in
            (0..<count).map { x in TileCoordinate(x: x, y: y, zoom: zoom) }
        }
    }
}
