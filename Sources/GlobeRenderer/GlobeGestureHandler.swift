import UIKit
import SceneKit
import simd

/// Manages pan, pinch, and scroll-wheel gestures for a GlobeView.
/// Only instantiated when `gesturesEnabled` is true.
final class GlobeGestureHandler: NSObject, UIGestureRecognizerDelegate {

    weak var globeView: GlobeView?
    var lockNorth: Bool = true

    // Momentum state
    private var momentumDisplayLink: CADisplayLink?
    private var momentumVelocity: CGPoint = .zero
    private var momentumStart: CFTimeInterval = 0
    private let momentumDuration: CFTimeInterval = 0.7

    var hasMomentum: Bool { momentumDisplayLink != nil }

    init(globeView: GlobeView) {
        self.globeView = globeView
        super.init()
    }

    func installGestures(on view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedScrollTypesMask = [.continuous, .discrete]
        scroll.maximumNumberOfTouches = 0
        view.addGestureRecognizer(scroll)
    }

    func stopMomentum() {
        momentumDisplayLink?.invalidate()
        momentumDisplayLink = nil
    }

    // MARK: - Gesture Handlers

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let globeView else { return }

        if gesture.state == .began {
            stopMomentum()
            globeView.startContinuousRendering()
        }

        if gesture.state == .changed {
            let translation = gesture.translation(in: globeView.scnView)
            applyPan(translationX: Float(translation.x), translationY: Float(translation.y))
            gesture.setTranslation(.zero, in: globeView.scnView)
        }

        if gesture.state == .ended || gesture.state == .cancelled {
            let velocity = gesture.velocity(in: globeView.scnView)
            if abs(velocity.x) > 50 || abs(velocity.y) > 50 {
                startMomentum(velocity: velocity)
            } else {
                globeView.stopContinuousRenderingIfIdle()
            }
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let globeView else { return }

        if gesture.state == .began {
            stopMomentum()
            globeView.startContinuousRendering()
        }

        if gesture.state == .changed {
            let oldSurfaceDist = globeView.cameraDistance - 1.0
            var newSurfaceDist = oldSurfaceDist / Float(gesture.scale)
            globeView.cameraDistance = max(globeView.minDistance, min(globeView.maxDistance, 1.0 + newSurfaceDist))
            newSurfaceDist = globeView.cameraDistance - 1.0
            gesture.scale = 1.0

            zoomAroundPoint(gesture.location(in: globeView.scnView), oldSurfaceDist: oldSurfaceDist, newSurfaceDist: newSurfaceDist)
            globeView.updateCameraTransform()
        }

        if gesture.state == .ended || gesture.state == .cancelled {
            globeView.stopContinuousRenderingIfIdle()
        }
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard let globeView else { return }

        stopMomentum()
        globeView.startContinuousRendering()

        let oldSurfaceDist = globeView.cameraDistance - 1.0
        let translation = gesture.translation(in: globeView.scnView)
        let zoomSensitivity: Float = 0.01
        var newSurfaceDist = oldSurfaceDist * (1.0 - Float(translation.y) * zoomSensitivity)
        globeView.cameraDistance = max(globeView.minDistance, min(globeView.maxDistance, 1.0 + newSurfaceDist))
        newSurfaceDist = globeView.cameraDistance - 1.0
        gesture.setTranslation(.zero, in: globeView.scnView)

        zoomAroundPoint(gesture.location(in: globeView.scnView), oldSurfaceDist: oldSurfaceDist, newSurfaceDist: newSurfaceDist)
        globeView.updateCameraTransform()

        if gesture.state == .ended || gesture.state == .cancelled {
            globeView.stopContinuousRenderingIfIdle()
        }
    }

    // MARK: - Pan Math

    func applyPan(translationX: Float, translationY: Float) {
        guard let globeView else { return }

        let fov = Float(globeView.cameraNode.camera?.fieldOfView ?? 60) * .pi / 180
        let viewHeight = max(Float(globeView.cachedViewportSize.height), 1)
        let sensitivity = fov / viewHeight * (globeView.cameraDistance - 1.0)

        let dx = translationX * sensitivity
        let dy = translationY * sensitivity

        let cameraUp = simd_normalize(globeView.cameraOrientation.act(SIMD3<Float>(0, 1, 0)))
        let cameraRight = simd_normalize(globeView.cameraOrientation.act(SIMD3<Float>(1, 0, 0)))

        let rotH = simd_quatf(angle: -dx, axis: cameraUp)
        let rotV = simd_quatf(angle: -dy, axis: cameraRight)

        globeView.cameraOrientation = simd_normalize(rotV * rotH * globeView.cameraOrientation)

        if lockNorth {
            globeView.enforceNorthUp()
        }
        globeView.updateCameraTransform()
        globeView.notifyCameraChanged()
    }

    // MARK: - Zoom Around Point

    private func zoomAroundPoint(_ screenPoint: CGPoint, oldSurfaceDist: Float, newSurfaceDist: Float) {
        guard let globeView else { return }

        let offsetX = Float(screenPoint.x - globeView.cachedViewportSize.width / 2)
        let offsetY = Float(screenPoint.y - globeView.cachedViewportSize.height / 2)
        let fov = Float(globeView.cameraNode.camera?.fieldOfView ?? 60) * .pi / 180
        let viewHeight = max(Float(globeView.cachedViewportSize.height), 1)
        let compensation = fov / viewHeight * (oldSurfaceDist - newSurfaceDist)

        let cameraUp = simd_normalize(globeView.cameraOrientation.act(SIMD3<Float>(0, 1, 0)))
        let cameraRight = simd_normalize(globeView.cameraOrientation.act(SIMD3<Float>(1, 0, 0)))
        let rotH = simd_quatf(angle: offsetX * compensation, axis: cameraUp)
        let rotV = simd_quatf(angle: offsetY * compensation, axis: cameraRight)
        globeView.cameraOrientation = simd_normalize(rotV * rotH * globeView.cameraOrientation)

        if lockNorth {
            globeView.enforceNorthUp()
        }
        globeView.notifyCameraChanged()
    }

    // MARK: - Momentum

    private func startMomentum(velocity: CGPoint) {
        momentumVelocity = velocity
        momentumStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(momentumTick))
        link.add(to: .main, forMode: .common)
        momentumDisplayLink = link
    }

    @objc private func momentumTick(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - momentumStart
        guard elapsed < momentumDuration else {
            stopMomentum()
            globeView?.stopContinuousRenderingIfIdle()
            return
        }

        let t = Float(elapsed / momentumDuration)
        let factor = (1 - t) * (1 - t)
        let dt = Float(link.targetTimestamp - link.timestamp)

        let tx = Float(momentumVelocity.x) * factor * dt
        let ty = Float(momentumVelocity.y) * factor * dt
        applyPan(translationX: tx, translationY: ty)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let isPanPinch = (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer) ||
                         (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
        return isPanPinch
    }
}
