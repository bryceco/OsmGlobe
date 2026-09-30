import Foundation

/// A source of map tile imagery. Conform to this protocol to provide
/// tiles from any slippy-map-compatible tile server.
public protocol TileSource {
    /// Returns the URL for the given tile coordinate.
    /// Called from a background thread; must be safe to call concurrently.
    func tileURL(for coordinate: TileCoordinate) -> URL

    /// The directory where tile images are cached on disk.
    /// The package stores tiles as `{zoom}/{x}/{y}.png` inside this directory.
    /// The host app is responsible for creating this directory and cleaning it up.
    var cacheDirectory: URL { get }
}

/// Built-in OpenStreetMap tile source.
public struct OpenStreetMapTileSource: TileSource {
    private let prefixes = ["a", "b", "c"]

    public let cacheDirectory: URL

    /// Creates an OpenStreetMap tile source.
    /// - Parameter cacheDirectory: Where to store cached tiles. If nil, uses
    ///   a default location in the app's Caches directory.
    public init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.cacheDirectory = caches.appendingPathComponent("GlobeRenderer/openstreetmap", isDirectory: true)
        }
    }

    public func tileURL(for coordinate: TileCoordinate) -> URL {
        let prefix = prefixes[(coordinate.x + coordinate.y) % prefixes.count]
        return URL(string: "https://\(prefix).tile.openstreetmap.org/\(coordinate.zoom)/\(coordinate.x)/\(coordinate.y).png")!
    }
}
