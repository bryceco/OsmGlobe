//
//  ViewController.swift
//  OsmGlobe
//
//  Created by Bryce Cogswell on 5/8/21.
//

import UIKit
import SceneKit

class GlobeViewController: UIViewController {
	@IBOutlet var scnView: SCNView!

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		self.view.transform = CGAffineTransform(scaleX: 1, y: -1)

		scnView.backgroundColor = .black

		// Do any additional setup after loading the view.
		scnView.allowsCameraControl = true
		scnView.scene = SCNScene()

		let sphereGeom = SCNSphere(radius: 1.0)
		let sphereNode = SCNNode(geometry: sphereGeom)

		let material = SCNMaterial()
		material.diffuse.contents = GlobeImageLayer()

		sphereNode.geometry?.materials = [material]
		scnView.scene?.rootNode.addChildNode(sphereNode)
	}
}

