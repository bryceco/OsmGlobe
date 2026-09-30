import SceneKit

class GlobeScene {
    let scene: SCNScene
    let globeRootNode: SCNNode
    private var quadtree: TileQuadtree

    init(tileSource: TileSource) {
        scene = SCNScene()

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.intensity = 1000
        scene.rootNode.addChildNode(ambientLight)

        globeRootNode = SCNNode()
        scene.rootNode.addChildNode(globeRootNode)

        quadtree = TileQuadtree(rootNode: globeRootNode, tileSource: tileSource)
    }

    var pendingDownloadCount: Int { quadtree.pendingDownloadCount }
    var lastPendingCount: Int { quadtree.lastPendingCount }

    var onTileLoaded: (() -> Void)? {
        get { quadtree.onTileLoaded }
        set { quadtree.onTileLoaded = newValue }
    }

    func reset(tileSource: TileSource) {
        quadtree.reset(tileSource: tileSource)
    }

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
