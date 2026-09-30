import SceneKit

class TileGeometryBuilder {
    /// Choose subdivisions based on zoom: high-zoom tiles cover tiny areas
    /// where sphere curvature is negligible, so fewer subdivisions are fine.
    private static func subdivisions(forZoom zoom: Int) -> Int {
        switch zoom {
        case 0...3:  return 16
        case 4...5:  return 8
        case 6...7:  return 4
        default:     return 2
        }
    }

    func buildGeometry(for tile: TileCoordinate) -> SCNGeometry {
        let subdivisions = Self.subdivisions(forZoom: tile.zoom)
        let bounds = tile.geographicBounds
        let latStep = (bounds.maxLat - bounds.minLat) / Double(subdivisions)
        let lonStep = (bounds.maxLon - bounds.minLon) / Double(subdivisions)

        let vertexCount = (subdivisions + 1) * (subdivisions + 1)
        var positions = [SCNVector3]()
        var normals = [SCNVector3]()
        var texCoords = [CGPoint]()
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        texCoords.reserveCapacity(vertexCount)

        for row in 0...subdivisions {
            let lat = bounds.maxLat - Double(row) * latStep
            let v = CGFloat(row) / CGFloat(subdivisions)

            for col in 0...subdivisions {
                let lon = bounds.minLon + Double(col) * lonStep
                let u = CGFloat(col) / CGFloat(subdivisions)

                let pos = GlobeMath.geographicToCartesian(lat: lat, lon: lon)
                positions.append(pos)
                normals.append(pos)
                texCoords.append(CGPoint(x: u, y: v))
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity(subdivisions * subdivisions * 6)

        for row in 0..<subdivisions {
            for col in 0..<subdivisions {
                let topLeft = UInt32(row * (subdivisions + 1) + col)
                let topRight = topLeft + 1
                let bottomLeft = topLeft + UInt32(subdivisions + 1)
                let bottomRight = bottomLeft + 1

                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }

        let positionSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let texCoordSource = SCNGeometrySource(textureCoordinates: texCoords)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        return SCNGeometry(
            sources: [positionSource, normalSource, texCoordSource],
            elements: [element]
        )
    }
}
