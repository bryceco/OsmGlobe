import UIKit
import SceneKit
import simd

/// A view that renders an interactive 3D globe with tiled map imagery.
public final class GlobeView: UIView, SCNSceneRendererDelegate {

    // MARK: - Public API

    /// The tile imagery source. Changing this at runtime clears all loaded
    /// tiles and begins loading from the new source.
    public var tileSource: TileSource {
        didSet {
            globeScene.reset(tileSource: tileSource)
            setNeedsRender()
        }
    }

    /// The current camera position in geographic coordinates.
    ///
    /// Reading always returns the current position. Writing moves the camera
    /// immediately and cancels any active momentum animation.
    public var camera: GlobeCamera {
        get {
            GlobeCamera(orientation: cameraOrientation, distance: cameraDistance)
        }
        set {
            gestureHandler?.stopMomentum()
            cameraOrientation = newValue.cameraOrientation
            cameraDistance = newValue.cameraDistance
            if lockNorth { enforceNorthUp() }
            updateCameraTransform()
            startContinuousRendering()
        }
    }

    /// Whether the camera always keeps geographic north at the top of the screen.
    public var lockNorth: Bool = true {
        didSet {
            gestureHandler?.lockNorth = lockNorth
            if lockNorth {
                enforceNorthUp()
                updateCameraTransform()
                setNeedsRender()
            }
        }
    }

    /// Whether the view installs its own gesture recognizers for pan, pinch,
    /// and scroll. When false, the hosting app must set `camera` directly.
    /// Set this before the view appears; changes after have no effect.
    public var gesturesEnabled: Bool = true

    /// Called on the main thread whenever the camera position changes due to
    /// gesture interaction. Not called when the host sets `camera` directly.
    public var onCameraChanged: ((GlobeCamera) -> Void)?

    /// Animates the camera to orient north at the top of the screen.
    public func orientNorth(animated: Bool = true) {
        startContinuousRendering()
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            SCNTransaction.completionBlock = { [weak self] in
                self?.stopContinuousRenderingIfIdle()
            }
        }
        enforceNorthUp()
        updateCameraTransform()
        if animated {
            SCNTransaction.commit()
        } else {
            stopContinuousRenderingIfIdle()
        }
    }

    /// Whether to show the download progress indicator (spinner + count).
    public var showsDownloadIndicator: Bool = true {
        didSet { loadingStack.isHidden = !showsDownloadIndicator }
    }

    /// Whether to show the coordinate label (lat, lon, zoom).
    public var showsCoordinateLabel: Bool = true {
        didSet { infoLabel.isHidden = !showsCoordinateLabel }
    }

    /// The number of tile downloads currently in flight.
    public var pendingDownloadCount: Int { globeScene.pendingDownloadCount }

    // MARK: - Internal state (accessed by GlobeGestureHandler)

    var cameraOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var cameraDistance: Float = 3.0
    let minDistance: Float = 1.00002
    let maxDistance: Float = 10.0
    var cachedViewportSize: CGSize = .zero
    var scnView: SCNView!
    var cameraNode: SCNNode!

    private var globeScene: GlobeScene!
    private var gestureHandler: GlobeGestureHandler?

    // UI chrome
    private var activityIndicator: UIActivityIndicatorView!
    private var downloadCountLabel: UILabel!
    private var loadingStack: UIStackView!
    private var infoLabel: UILabel!

    // Download indicator delay
    private var downloadsPendingSince: CFTimeInterval = 0
    private let indicatorDelay: CFTimeInterval = 0.3

    // MARK: - Initialization

    /// Creates a globe view with the given tile source.
    public init(frame: CGRect = .zero, tileSource: TileSource = OpenStreetMapTileSource()) {
        self.tileSource = tileSource
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.tileSource = OpenStreetMapTileSource()
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        scnView = SCNView(frame: bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false
        scnView.delegate = self
        scnView.isPlaying = false
        addSubview(scnView)

        globeScene = GlobeScene(tileSource: tileSource)
        globeScene.onTileLoaded = { [weak self] in
            DispatchQueue.main.async {
                self?.setNeedsRender()
            }
        }
        scnView.scene = globeScene.scene

        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.00001
        cameraNode.camera?.zFar = 100
        globeScene.scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
        updateCameraTransform()

        setupUI()
    }

    private func setupUI() {
        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        downloadCountLabel = UILabel()
        downloadCountLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        downloadCountLabel.textColor = .white
        downloadCountLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadCountLabel.isHidden = true

        loadingStack = UIStackView(arrangedSubviews: [activityIndicator, downloadCountLabel])
        loadingStack.axis = .horizontal
        loadingStack.spacing = 4
        loadingStack.alignment = .center
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingStack.isHidden = !showsDownloadIndicator
        addSubview(loadingStack)

        infoLabel = UILabel()
        infoLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        infoLabel.layer.cornerRadius = 6
        infoLabel.clipsToBounds = true
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.isHidden = !showsCoordinateLabel
        addSubview(infoLabel)

        NSLayoutConstraint.activate([
            loadingStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            loadingStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),

            infoLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            infoLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            cachedViewportSize = scnView.bounds.size
            if gesturesEnabled && gestureHandler == nil {
                let handler = GlobeGestureHandler(globeView: self)
                handler.lockNorth = lockNorth
                handler.installGestures(on: scnView)
                gestureHandler = handler
            }
            startContinuousRendering()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        cachedViewportSize = scnView.bounds.size
    }

    // MARK: - Camera Transform

    func updateCameraTransform() {
        let position = cameraOrientation.act(SIMD3<Float>(0, 0, cameraDistance))
        cameraNode.position = SCNVector3(position.x, position.y, position.z)
        let up = cameraOrientation.act(SIMD3<Float>(0, 1, 0))
        cameraNode.look(at: SCNVector3Zero, up: SCNVector3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
    }

    func enforceNorthUp() {
        let forward = simd_normalize(cameraOrientation.act(SIMD3<Float>(0, 0, 1)))
        let worldUp = SIMD3<Float>(0, 1, 0)

        let northUp = worldUp - simd_dot(worldUp, forward) * forward
        let northUpLen = simd_length(northUp)

        guard northUpLen > 0.001 else { return }

        let up = northUp / northUpLen
        let right = simd_cross(up, forward)
        cameraOrientation = simd_normalize(simd_quatf(simd_float3x3(columns: (right, up, forward))))
    }

    func notifyCameraChanged() {
        onCameraChanged?(camera)
    }

    // MARK: - Rendering Control

    func setNeedsRender() {
        if scnView.isPlaying { return }
        scnView.setNeedsDisplay()
    }

    func startContinuousRendering() {
        scnView.isPlaying = true
    }

    func stopContinuousRenderingIfIdle() {
        guard gestureHandler?.hasMomentum != true,
              globeScene.pendingDownloadCount == 0 else { return }
        scnView.isPlaying = false
    }

    // MARK: - SCNSceneRendererDelegate

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
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

        let camPos = cameraWorldPosition
        let camLen = sqrt(camPos.x * camPos.x + camPos.y * camPos.y + camPos.z * camPos.z)
        let lat = asin(camPos.y / camLen) * 180.0 / .pi
        let lon = atan2(camPos.z, -camPos.x) * 180.0 / .pi
        let zoom = log2(.pi / acos(min(1.0, 1.0 / camLen)))

        let pending = globeScene.lastPendingCount
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if pending > 0 {
                if self.downloadsPendingSince == 0 {
                    self.downloadsPendingSince = CACurrentMediaTime()
                }
                let elapsed = CACurrentMediaTime() - self.downloadsPendingSince
                if elapsed >= self.indicatorDelay {
                    self.activityIndicator.startAnimating()
                    self.downloadCountLabel.text = "\(pending)"
                    self.downloadCountLabel.isHidden = false
                }
            } else {
                self.downloadsPendingSince = 0
                self.activityIndicator.stopAnimating()
                self.downloadCountLabel.isHidden = true
                self.stopContinuousRenderingIfIdle()
            }
            self.infoLabel.text = String(format: "  %.4f, %.4f  Z%.1f  ", lat, lon, zoom)
        }
    }
}
