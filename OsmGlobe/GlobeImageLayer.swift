//
//  GlobeLayer.swift
//  OsmGlobe
//
//  Created by Bryce Cogswell on 5/8/21.
//

import UIKit

// take a projected web mercator image and convert it to equirectangular
fileprivate class MercatorUnproject: CIFilter {
	var inputImage: CIImage?
	let unproject = CIWarpKernel(source: """
		kernel vec2 unprojectMercator(float imageHeight) {
			float pi = 3.1415926535897932384626433;
			vec2 dst = destCoord();
			float y = -((dst.y / imageHeight) - 0.5);	// -0.5..0.5
			y = 90.0 - 360.0 * atan(exp(y * 2.0 * pi)) / pi;	// latitude in degrees
			y = y + 90.0;
			y = y * imageHeight / 180.0;
			return vec2(dst.x, y);
		}
		""")
	let project = CIWarpKernel(source: """
		kernel vec2 projectMercator(float imageHeight) {
			float pi = 3.1415926535897932384626433;
			vec2 dst = destCoord();
			float y = ((dst.y / imageHeight) - 0.5);	// -0.5..0.5
			y = -y; // because origin is lower left?
			y = y * pi;	// -pi/2..pi/2	(latitude in radians)
			y = sin(y);	// sin(latitude)
			y = 0.5 - log((1 + y) / (1 - y)) / (4 * pi);	// 0..1
			y = y * imageHeight;
			return vec2(dst.x, y);
		}
		""")

	override var outputImage: CIImage? {
		guard let inputImage = inputImage,
			  let kernel = project else { return nil }
		let arguments = [ inputImage.extent.height ]
		return kernel.apply( extent: inputImage.extent,
							 roiCallback: {	(index, rect) in return rect },
							 image: inputImage,
							 arguments: arguments as [AnyObject])
	}
}


fileprivate class TilesLayer: CATiledLayer {
	let url = "https://{switch:a,b,c}.tile.openstreetmap.org/{z}/{x}/{y}.png"

	override init() {
		super.init()
		self.levelsOfDetail = 18
		self.tileSize = CGSize(width: 256,height: 256)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func urlFor(x:Int, y:Int, z:Int) -> URL {
		var url = self.url
		// handle switch in URL
		if let begin = url.range(of: "{switch:"),
		   let end = url[begin.upperBound...].range(of: "}")
		{
			let list = url[begin.upperBound..<end.lowerBound].components(separatedBy: ",")
			if list.count > 0 {
				let t = list[(x+y) % list.count]
				url.replaceSubrange(begin.lowerBound..<end.upperBound, with: t)
			}
		}
		url = url.replacingOccurrences(of: "{x}", with: String(x))
		url = url.replacingOccurrences(of: "{y}", with: String(y))
		url = url.replacingOccurrences(of: "{z}", with: String(z))
		return URL(string: url)!
	}

	override func draw(in ctx: CGContext) {
		let bounds = ctx.boundingBoxOfClipPath
		print("bounds = \(bounds), trans = \(ctx.ctm)")

		if ctx.ctm.a > 1 {
			print("render")
		}

		let z = Int( log2(self.frame.width / 256.0) )
		for x in Int(bounds.minX/256.0)..<Int(bounds.maxX/256.0) {
			for y in Int(bounds.minY/256.0)..<Int(bounds.maxY/256.0) {
				let url = urlFor(x:x, y:y, z:z)
				if let data = try? Data(contentsOf: url),
				   let image = UIImage(data: data)
				{
					let y = ctx.ctm.a > 1 ? Int(bounds.maxY/256.0)-1-y : y
					ctx.draw(image.cgImage!, in: CGRect(x: x*256, y: y*256, width: 256, height: 256))
				} else {
					print("failed: x \(x), y \(y), z \(z)")
				}
			}
		}
	}
}

class GlobeImageLayer: CALayer {
	private let tileLayer = TilesLayer()
	private let maxLat: CGFloat = 85.051129 / 90.0

	override init() {
		super.init()
		let size: CGFloat = 1024.0
		self.frame = CGRect(x: 0, y: 0, width: size, height: size / maxLat)
		tileLayer.frame = CGRect(x: 0.0,
								 y: (self.bounds.height - size)/2,
								 width: size,
								 height: size)
		self.addSublayer( tileLayer )
		tileLayer.setNeedsDisplay()
		self.backgroundColor = UIColor.gray.cgColor

		DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(3)) {
			self.unstretch()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func imageForLayer() -> UIImage? {
		let scale = UIScreen.main.scale
		let size = CGSize(width: self.bounds.size.width * scale, height: self.bounds.size.height * scale)
		let rgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
		let _ = CGContext(data: nil,
						   width: Int(size.width), height: Int(size.height),
						   bitsPerComponent: 8, bytesPerRow: 0,
						   space: rgbColorSpace,
						   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
		return nil
	}

	func unstretch() {
		let renderer = UIGraphicsImageRenderer(size: tileLayer.bounds.size)
		var uiImage = renderer.image { tileLayer.render(in: $0.cgContext) }
		var ciImage = CIImage(image: uiImage)

		#if true
		let filter = MercatorUnproject()
		filter.inputImage = ciImage
		ciImage = filter.outputImage
		#endif

		var cgImage = CIContext().createCGImage(ciImage!, from: ciImage!.extent)!

		if false && uiImage.scale > 1 {
			uiImage = UIImage(cgImage: cgImage, scale: uiImage.scale, orientation: uiImage.imageOrientation)
			UIGraphicsBeginImageContext(self.bounds.size)
			uiImage.draw(in: CGRect(origin: CGPoint(), size: self.bounds.size))
			uiImage = UIGraphicsGetImageFromCurrentImageContext()!
			UIGraphicsEndImageContext()
			cgImage = uiImage.cgImage!
		}

		let newLayer = CALayer()
		newLayer.frame = tileLayer.frame
		newLayer.contents = cgImage
		self.addSublayer( newLayer )

		self.tileLayer.removeFromSuperlayer()
	}
}
