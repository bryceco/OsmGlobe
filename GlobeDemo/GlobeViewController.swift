import UIKit
import GlobeRenderer

class GlobeViewController: UIViewController {
    private var globeView: GlobeView!
    private var northButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        globeView = GlobeView(frame: view.bounds, tileSource: OpenStreetMapTileSource())
        globeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        globeView.lockNorth = true
        globeView.showsDownloadIndicator = true
        globeView.showsCoordinateLabel = true
        view.addSubview(globeView)

        northButton = UIButton(type: .system)
        northButton.setImage(UIImage(systemName: "location.north.fill"), for: .normal)
        northButton.tintColor = .white
        northButton.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
        northButton.layer.cornerRadius = 20
        northButton.translatesAutoresizingMaskIntoConstraints = false
        northButton.addTarget(self, action: #selector(orientNorthTapped), for: .touchUpInside)
        northButton.isHidden = globeView.lockNorth
        view.addSubview(northButton)
        NSLayoutConstraint.activate([
            northButton.widthAnchor.constraint(equalToConstant: 40),
            northButton.heightAnchor.constraint(equalToConstant: 40),
            northButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            northButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    @objc private func orientNorthTapped() {
        globeView.orientNorth()
    }

    override var prefersStatusBarHidden: Bool { true }
}
