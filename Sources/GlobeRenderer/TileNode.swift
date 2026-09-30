import SceneKit
import UIKit

class TileNode {
    let coordinate: TileCoordinate
    let scnNode: SCNNode
    private let material: SCNMaterial

    init(coordinate: TileCoordinate, geometry: SCNGeometry) {
        self.coordinate = coordinate

        material = SCNMaterial()
        material.isDoubleSided = false
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.darkGray
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        geometry.materials = [material]

        scnNode = SCNNode(geometry: geometry)
        scnNode.name = coordinate.description
    }

    func setTexture(_ image: UIImage) {
        material.diffuse.contents = image
    }
}
