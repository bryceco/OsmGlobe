import UIKit

class TileCache {
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    init(cacheDirectory: URL) {
        diskCacheURL = cacheDirectory
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = 500
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    private func cacheKey(for tile: TileCoordinate) -> NSString {
        "\(tile.zoom)/\(tile.x)/\(tile.y)" as NSString
    }

    private func diskPath(for tile: TileCoordinate) -> URL {
        let dir = diskCacheURL
            .appendingPathComponent("\(tile.zoom)", isDirectory: true)
            .appendingPathComponent("\(tile.x)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(tile.y).png")
    }

    func memoryImage(for tile: TileCoordinate) -> UIImage? {
        memoryCache.object(forKey: cacheKey(for: tile))
    }

    func diskImage(for tile: TileCoordinate) -> UIImage? {
        let path = diskPath(for: tile)
        guard let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    func storeInMemory(_ image: UIImage, for tile: TileCoordinate) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: cacheKey(for: tile), cost: cost)
    }

    func storeToDisk(_ data: Data, for tile: TileCoordinate) {
        let path = diskPath(for: tile)
        try? data.write(to: path, options: .atomic)
    }

    func clearMemory() {
        memoryCache.removeAllObjects()
    }
}
