# OsmGlobe
A 3-D globe covered with Web Mercator (OSM) tiles

A work in progress:

* The globe is created via SceneKit
* The tiles are a CATiledLayer applied to a SCNMaterial
* The full set of tiles is then transformed (projected) via a CoreImage filter to compensate for the fact that they are Web Mercator instead of Equirectangular
