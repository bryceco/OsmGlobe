import UIKit

enum TileFetchError: Error {
    case invalidResponse
}

class TileFetcher {
    private let session: URLSession
    let cache: TileCache
    private let tileSource: TileSource

    init(tileSource: TileSource) {
        self.tileSource = tileSource
        self.cache = TileCache(cacheDirectory: tileSource.cacheDirectory)

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func fetchTile(_ tile: TileCoordinate) async throws -> UIImage {
        if let cached = cache.memoryImage(for: tile) {
            return cached
        }

        if let diskImage = cache.diskImage(for: tile) {
            cache.storeInMemory(diskImage, for: tile)
            return diskImage
        }

        let url = tileSource.tileURL(for: tile)
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
}
