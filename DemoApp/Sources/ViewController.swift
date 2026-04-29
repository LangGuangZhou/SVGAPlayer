import UIKit
import SVGAPlayerSwift

final class ViewController: UIViewController {
    private let player = SVGAPlayer()
    private let parser = SVGAParser()
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupPlayer()
        setupStatusLabel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playLocalSVGA()
    }

    private func setupPlayer() {
        player.translatesAutoresizingMaskIntoConstraints = false
        player.backgroundColor = .secondarySystemBackground
        player.loops = 0
        view.addSubview(player)

        NSLayoutConstraint.activate([
            player.widthAnchor.constraint(equalToConstant: 240),
            player.heightAnchor.constraint(equalToConstant: 240),
            player.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            player.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupStatusLabel() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = "Loading rocket6.svga..."
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: player.bottomAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func playLocalSVGA() {
        parser.parse(withNamed: "rocket6", in: .main) { [weak self] videoItem in
            guard let self, let videoItem else {
                self?.statusLabel.text = "Failed to load rocket6.svga"
                return
            }
            self.player.videoItem = videoItem
            self.player.startAnimation()
            self.statusLabel.text = "Playing rocket6.svga"
        } failureBlock: { [weak self] error in
            let message = error?.localizedDescription ?? "unknown error"
            self?.statusLabel.text = "Load error: \(message)\nPut rocket6.svga in DemoApp/Resources"
        }
    }
}
