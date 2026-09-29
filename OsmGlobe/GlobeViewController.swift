import SceneKit
import UIKit
import simd

class GlobeViewController: UIViewController, SCNSceneRendererDelegate {
    private var scnView: SCNView!
    private var globeScene: GlobeScene!
    private var cameraNode: SCNNode!

    /// Camera orbit as a quaternion. The camera position is orientation.act((0,0,distance)).
    private var cameraOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var cameraDistance: Float = 3.0

    private let minDistance: Float = 1.002
    private let maxDistance: Float = 10.0

    /// Cached viewport size, updated on main thread for safe access from the render thread.
    private var cachedViewportSize: CGSize = .zero

    private var activityIndicator: UIActivityIndicatorView!
    private var downloadCountLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false
        scnView.delegate = self
        scnView.isPlaying = true // Continuous rendering for tile updates
        view.addSubview(scnView)

        globeScene = GlobeScene()
        scnView.scene = globeScene.scene

        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 100
        globeScene.scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
        updateCameraTransform()
        cachedViewportSize = scnView.bounds.size

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        scnView.addGestureRecognizer(pinchGesture)

        let scrollGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollGesture.allowedScrollTypesMask = [.continuous, .discrete]
        scrollGesture.maximumNumberOfTouches = 0 // Only respond to scroll wheel, not touches
        scnView.addGestureRecognizer(scrollGesture)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        downloadCountLabel = UILabel()
        downloadCountLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        downloadCountLabel.textColor = .white
        downloadCountLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadCountLabel.isHidden = true

        let loadingStack = UIStackView(arrangedSubviews: [activityIndicator, downloadCountLabel])
        loadingStack.axis = .horizontal
        loadingStack.spacing = 4
        loadingStack.alignment = .center
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingStack)
        NSLayoutConstraint.activate([
            loadingStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            loadingStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])

        let northButton = UIButton(type: .system)
        northButton.setImage(UIImage(systemName: "location.north.fill"), for: .normal)
        northButton.tintColor = .white
        northButton.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
        northButton.layer.cornerRadius = 20
        northButton.translatesAutoresizingMaskIntoConstraints = false
        northButton.addTarget(self, action: #selector(orientNorth), for: .touchUpInside)
        view.addSubview(northButton)
        NSLayoutConstraint.activate([
            northButton.widthAnchor.constraint(equalToConstant: 40),
            northButton.heightAnchor.constraint(equalToConstant: 40),
            northButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            northButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func updateCameraTransform() {
        let position = cameraOrientation.act(SIMD3<Float>(0, 0, cameraDistance))
        cameraNode.position = SCNVector3(position.x, position.y, position.z)
        let up = cameraOrientation.act(SIMD3<Float>(0, 1, 0))
        cameraNode.look(at: SCNVector3Zero, up: SCNVector3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: scnView)
        // Scale rotation so the surface point tracks the finger/cursor.
        let fov = Float(cameraNode.camera?.fieldOfView ?? 60) * .pi / 180
        let viewHeight = max(Float(cachedViewportSize.height), 1)
        let sensitivity = fov / viewHeight * (cameraDistance - 1.0)

        let dx = Float(translation.x) * sensitivity
        let dy = Float(translation.y) * sensitivity

        // Rotate around the camera's local axes so panning feels natural at all latitudes.
        let cameraUp = simd_normalize(cameraOrientation.act(SIMD3<Float>(0, 1, 0)))
        let cameraRight = simd_normalize(cameraOrientation.act(SIMD3<Float>(1, 0, 0)))

        let rotH = simd_quatf(angle: -dx, axis: cameraUp)
        let rotV = simd_quatf(angle: -dy, axis: cameraRight)

        cameraOrientation = simd_normalize(rotV * rotH * cameraOrientation)

        gesture.setTranslation(.zero, in: scnView)
        updateCameraTransform()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            // Zoom the surface distance so the rate feels consistent at all altitudes.
            var surfaceDist = cameraDistance - 1.0
            surfaceDist /= Float(gesture.scale)
            cameraDistance = max(minDistance, min(maxDistance, 1.0 + surfaceDist))
            gesture.scale = 1.0
            updateCameraTransform()
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: scnView)
        let zoomSensitivity: Float = 0.01
        var surfaceDist = cameraDistance - 1.0
        surfaceDist *= 1.0 - Float(translation.y) * zoomSensitivity
        cameraDistance = max(minDistance, min(maxDistance, 1.0 + surfaceDist))
        gesture.setTranslation(.zero, in: scnView)
        updateCameraTransform()
    }

    @objc private func orientNorth() {
        // Keep the same viewing direction but remove any accumulated roll
        // so that the meridian facing the user becomes vertical.
        let forward = simd_normalize(cameraOrientation.act(SIMD3<Float>(0, 0, 1)))
        let worldUp = SIMD3<Float>(0, 1, 0)

        // Project world-up onto the plane perpendicular to the viewing direction.
        let northUp = worldUp - simd_dot(worldUp, forward) * forward
        let northUpLen = simd_length(northUp)

        // If looking straight at a pole, north-up is undefined; do nothing.
        guard northUpLen > 0.001 else { return }

        let up = northUp / northUpLen
        let right = simd_cross(up, forward)

        // Build the target quaternion from the orthonormal basis (right, up, forward).
        let targetOrientation = simd_normalize(simd_quatf(simd_float3x3(columns: (right, up, forward))))

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        cameraOrientation = targetOrientation
        updateCameraTransform()
        SCNTransaction.commit()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pointOfView = renderer.pointOfView,
              let camera = pointOfView.camera else { return }

        let cameraWorldPosition = pointOfView.worldPosition
        let viewMatrix = SCNMatrix4Invert(pointOfView.worldTransform)
        let projectionMatrix = camera.projectionTransform
        let viewport = cachedViewportSize

        globeScene.update(
            cameraPosition: cameraWorldPosition,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            viewport: viewport
        )

        let pending = globeScene.pendingDownloadCount
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if pending > 0 {
                self.activityIndicator.startAnimating()
                self.downloadCountLabel.text = "\(pending)"
                self.downloadCountLabel.isHidden = false
            } else {
                self.activityIndicator.stopAnimating()
                self.downloadCountLabel.isHidden = true
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cachedViewportSize = scnView.bounds.size
    }

    override var prefersStatusBarHidden: Bool { true }
}
