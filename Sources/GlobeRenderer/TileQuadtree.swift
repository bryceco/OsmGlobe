import SceneKit
import UIKit

class TileQuadtree {
    private let rootNode: SCNNode
    private var tileFetcher: TileFetcher
    private let geometryBuilder = TileGeometryBuilder()
    private let stateLock = NSLock()

    /// Currently active tile nodes, keyed by tile coordinate.
    private var activeTiles: [TileCoordinate: TileNode] = [:]

    /// Tiles with textures loaded and stored in the fetcher's cache.
    private var loadedTextures: Set<TileCoordinate> = []

    /// In-flight download tasks.
    private var pendingDownloads: [TileCoordinate: Task<Void, Never>] = [:]

    private let baseZoom = 2
    private let maxZoom = 18

    /// If a tile's estimated screen size exceeds this, subdivide it.
    private let subdivisionThreshold: CGFloat = 256.0

    /// Track the previous set of desired tiles to avoid redundant work.
    private var previousDesiredTiles: Set<TileCoordinate> = []

    /// Set when a download completes, to trigger reconciliation without
    /// invalidating the entire desired-tile set.
    private var needsReconciliation = false

    /// Called on an arbitrary thread when a tile download completes, so the
    /// host can schedule a render pass.
    var onTileLoaded: (() -> Void)?

    /// Number of tiles currently being downloaded.
    var pendingDownloadCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingDownloads.count
    }

    /// After the most recent `update()`, how many downloads were in flight.
    /// Captured inside the lock to avoid races with fast-completing tasks.
    private(set) var lastPendingCount = 0

    init(rootNode: SCNNode, tileSource: TileSource) {
        self.rootNode = rootNode
        self.tileFetcher = TileFetcher(tileSource: tileSource)
    }

    /// Clears all state and switches to a new tile source.
    func reset(tileSource: TileSource) {
        stateLock.lock()
        defer { stateLock.unlock() }

        // Cancel all pending downloads
        for (_, task) in pendingDownloads {
            task.cancel()
        }
        pendingDownloads.removeAll()

        // Remove all scene nodes
        for (_, tileNode) in activeTiles {
            tileNode.scnNode.removeFromParentNode()
        }
        activeTiles.removeAll()
        loadedTextures.removeAll()
        previousDesiredTiles.removeAll()
        needsReconciliation = false
        lastPendingCount = 0

        // Create new fetcher with new source
        tileFetcher = TileFetcher(tileSource: tileSource)
    }

    // MARK: - Per-Frame Update

    func update(
        cameraPosition: SCNVector3,
        viewMatrix: SCNMatrix4,
        projectionMatrix: SCNMatrix4,
        viewport: CGSize
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let viewProjection = GlobeMath.multiplyMatrices(viewMatrix, projectionMatrix)

        // Step 1: Determine desired tiles via quadtree traversal
        var desiredTiles = Set<TileCoordinate>()
        let baseTiles = TileCoordinate.allTiles(atZoom: baseZoom)
        for tile in baseTiles {
            collectDesiredTiles(
                tile: tile,
                cameraPosition: cameraPosition,
                viewProjection: viewProjection,
                viewport: viewport,
                result: &desiredTiles
            )
        }

        assert(desiredTiles.count <= 200, "Tile calculation produced \(desiredTiles.count) tiles — this is excessive and risks rate limits")

        // Skip reconciliation if nothing changed
        guard desiredTiles != previousDesiredTiles || needsReconciliation else { return }
        previousDesiredTiles = desiredTiles
        needsReconciliation = false

        // Step 2: Decide which tile nodes to keep and which textures to apply.
        var nodesToKeep = Set<TileCoordinate>()
        var texturesToApply: [TileCoordinate: UIImage] = [:]

        for tile in desiredTiles {
            if let image = tileFetcher.cache.memoryImage(for: tile) {
                nodesToKeep.insert(tile)
                texturesToApply[tile] = image
                loadedTextures.insert(tile)
            } else if loadedTextures.contains(tile) && activeTiles[tile] != nil {
                nodesToKeep.insert(tile)
            } else {
                if let (ancestor, image) = nearestMemoryAncestor(of: tile) {
                    nodesToKeep.insert(ancestor)
                    texturesToApply[ancestor] = image
                }
                startDownload(for: tile)
            }
        }

        // Step 3: Reconcile scene nodes
        let currentSet = Set(activeTiles.keys)

        for tile in currentSet.subtracting(nodesToKeep) {
            activeTiles[tile]?.scnNode.removeFromParentNode()
            activeTiles.removeValue(forKey: tile)
        }

        for tile in nodesToKeep.subtracting(currentSet) {
            let geometry = geometryBuilder.buildGeometry(for: tile)
            let node = TileNode(coordinate: tile, geometry: geometry)
            if let image = texturesToApply[tile] {
                node.setTexture(image)
            }
            rootNode.addChildNode(node.scnNode)
            activeTiles[tile] = node
        }

        for (tile, image) in texturesToApply {
            activeTiles[tile]?.setTexture(image)
        }

        // Step 4: Cancel downloads for tiles no longer desired
        for (tile, task) in pendingDownloads where !desiredTiles.contains(tile) {
            task.cancel()
            pendingDownloads.removeValue(forKey: tile)
        }

        lastPendingCount = pendingDownloads.count
    }

    // MARK: - Quadtree Traversal

    private func collectDesiredTiles(
        tile: TileCoordinate,
        cameraPosition: SCNVector3,
        viewProjection: SCNMatrix4,
        viewport: CGSize,
        result: inout Set<TileCoordinate>
    ) {
        let center = tile.centerOnSphere

        let camDist = GlobeMath.distance(SCNVector3Zero, cameraPosition)
        if camDist > 1.0 {
            let horizonAngle = acos(1.0 / camDist)
            let dotProduct = (cameraPosition.x * center.x + cameraPosition.y * center.y + cameraPosition.z * center.z) / camDist
            let clampedDot = min(max(dotProduct, -1.0), 1.0)
            let toCenterAngle = acos(clampedDot)
            let tileAngularRadius = Float(.pi / Double(1 << tile.zoom))
            if toCenterAngle > horizonAngle + tileAngularRadius + 0.1 {
                return
            }
        }

        let screenSize = estimateScreenSize(
            tile: tile,
            cameraPosition: cameraPosition,
            viewProjection: viewProjection,
            viewport: viewport
        )

        if screenSize < 0 { return }

        if screenSize > subdivisionThreshold && tile.zoom < maxZoom {
            for child in tile.children {
                collectDesiredTiles(
                    tile: child,
                    cameraPosition: cameraPosition,
                    viewProjection: viewProjection,
                    viewport: viewport,
                    result: &result
                )
            }
        } else {
            result.insert(tile)
        }
    }

    private func estimateScreenSize(
        tile: TileCoordinate,
        cameraPosition: SCNVector3,
        viewProjection: SCNMatrix4,
        viewport: CGSize
    ) -> CGFloat {
        let bounds = tile.geographicBounds
        let corners = [
            GlobeMath.geographicToCartesian(lat: bounds.minLat, lon: bounds.minLon),
            GlobeMath.geographicToCartesian(lat: bounds.maxLat, lon: bounds.minLon),
            GlobeMath.geographicToCartesian(lat: bounds.maxLat, lon: bounds.maxLon),
            GlobeMath.geographicToCartesian(lat: bounds.minLat, lon: bounds.maxLon),
        ]

        var screenPoints: [CGPoint] = []
        var anyBehind = false
        for corner in corners {
            if let pt = GlobeMath.projectToScreen(corner, viewProjection: viewProjection, viewport: viewport) {
                screenPoints.append(pt)
            } else {
                anyBehind = true
            }
        }

        let margin = max(viewport.width, viewport.height) * 0.25
        if !screenPoints.isEmpty {
            if screenPoints.allSatisfy({ $0.x < -margin }) ||
               screenPoints.allSatisfy({ $0.x > viewport.width + margin }) ||
               screenPoints.allSatisfy({ $0.y < -margin }) ||
               screenPoints.allSatisfy({ $0.y > viewport.height + margin }) {
                return -1
            }
        }

        if anyBehind || screenPoints.count < 4 {
            return 0
        }

        let p = screenPoints
        let area = abs(
            (p[0].x * p[1].y - p[1].x * p[0].y) +
            (p[1].x * p[2].y - p[2].x * p[1].y) +
            (p[2].x * p[3].y - p[3].x * p[2].y) +
            (p[3].x * p[0].y - p[0].x * p[3].y)
        ) / 2.0

        return sqrt(area)
    }

    // MARK: - Placeholder Logic

    private func nearestMemoryAncestor(of tile: TileCoordinate) -> (TileCoordinate, UIImage)? {
        var current = tile.parent
        while let ancestor = current {
            if let image = tileFetcher.cache.memoryImage(for: ancestor) {
                return (ancestor, image)
            }
            current = ancestor.parent
        }
        return nil
    }

    // MARK: - Tile Downloading

    private func startDownload(for tile: TileCoordinate) {
        guard pendingDownloads[tile] == nil else { return }

        pendingDownloads[tile] = Task { [weak self] in
            guard let self = self else { return }
            do {
                let image = try await self.tileFetcher.fetchTile(tile)
                self.applyDownloadResult(tile: tile, image: image)
            } catch {
                self.clearPendingDownload(for: tile)
            }
        }
    }

    private func applyDownloadResult(tile: TileCoordinate, image: UIImage) {
        stateLock.lock()
        defer { stateLock.unlock() }
        loadedTextures.insert(tile)
        activeTiles[tile]?.setTexture(image)
        pendingDownloads.removeValue(forKey: tile)
        needsReconciliation = true
        let callback = onTileLoaded
        stateLock.unlock()
        callback?()
        stateLock.lock()
    }

    private func clearPendingDownload(for tile: TileCoordinate) {
        stateLock.lock()
        defer { stateLock.unlock() }
        pendingDownloads.removeValue(forKey: tile)
    }
}
