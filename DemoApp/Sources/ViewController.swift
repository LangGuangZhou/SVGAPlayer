import UIKit
import SVGAPlayerSwift

final class ViewController: UIViewController {
    private let player = SVGAPlayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupPlayer()
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
}
