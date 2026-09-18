import UIKit

enum TileFetchError: Error {
    case invalidResponse
}

class TileFetcher {
    private let session: URLSession
    let cache = TileCache()
    private let serverPrefixes = ["a", "b", "c"]

    init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil // We manage our own cache
        config.httpAdditionalHeaders = [
            "User-Agent": "OsmGlobe/1.0 iOS"
        ]
        session = URLSession(configuration: config)
    }

	var downloadCount = 0

    func fetchTile(_ tile: TileCoordinate) async throws -> UIImage {
        // Check memory cache
        if let cached = cache.memoryImage(for: tile) {
            return cached
        }

        // Check disk cache
        if let diskImage = cache.diskImage(for: tile) {
            cache.storeInMemory(diskImage, for: tile)
            return diskImage
        }

        // Download from network
        let url = tileURL(for: tile)
        // print("[TileFetcher] Downloading \(tile.zoom)/\(tile.x)/\(tile.y)")
		downloadCount += 1
		print("\(downloadCount) - \(url.absoluteString)")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let image = UIImage(data: data) else {
            throw TileFetchError.invalidResponse
        }

        cache.storeInMemory(image, for: tile)
        cache.storeToDisk(data, for: tile)

        return image
    }

    /// Check if a tile image is immediately available from cache.
    func cachedImage(for tile: TileCoordinate) -> UIImage? {
        if let mem = cache.memoryImage(for: tile) { return mem }
        if let disk = cache.diskImage(for: tile) {
            cache.storeInMemory(disk, for: tile)
            return disk
        }
        return nil
    }

    private func tileURL(for tile: TileCoordinate) -> URL {
        let prefix = serverPrefixes[(tile.x + tile.y) % serverPrefixes.count]
        return URL(string: "https://\(prefix).tile.openstreetmap.org/\(tile.zoom)/\(tile.x)/\(tile.y).png")!
    }
}
