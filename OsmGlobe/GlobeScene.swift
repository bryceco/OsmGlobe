import SceneKit

class GlobeScene {
    let scene: SCNScene
    let globeRootNode: SCNNode
    private let quadtree: TileQuadtree

    init() {
        scene = SCNScene()

        // Ambient light so tiles are uniformly lit
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.intensity = 1000
        scene.rootNode.addChildNode(ambientLight)

        // Root node for all tile geometry
        globeRootNode = SCNNode()
        scene.rootNode.addChildNode(globeRootNode)

        quadtree = TileQuadtree(rootNode: globeRootNode)
    }

    var pendingDownloadCount: Int { quadtree.pendingDownloadCount }

    func update(
        cameraPosition: SCNVector3,
        viewMatrix: SCNMatrix4,
        projectionMatrix: SCNMatrix4,
        viewport: CGSize
    ) {
        quadtree.update(
            cameraPosition: cameraPosition,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            viewport: viewport
        )
    }
}
