import UIKit

@objcMembers
final class SVGAImageView: SVGAPlayer {

    // MARK: - Inspectable & Public
    @IBInspectable var autoPlay: Bool = true
    @IBInspectable var imageName: String? {
        didSet { loadImageIfNeeded(oldValue: oldValue) }
    }

    /// Set value before setting imageName
    var enabledMemoryCache: Bool = false

    /// Callback when parse completed
    var parseCompleteBlock: ((Bool) -> Void)?

    // MARK: - Parser
    private static let sharedParser: SVGAParser = {
        SVGAParser()
    }()

    private static let enableMemoryParser: SVGAParser = {
        let p = SVGAParser()
        p.enabledMemoryCache = true
        return p
    }()

    // MARK: - Lifecycle
    override func didMoveToWindow() {
        super.didMoveToWindow()
        checkPlay()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        checkPlay()
    }

    override var alpha: CGFloat {
        didSet { checkPlay() }
    }

    override var isHidden: Bool {
        didSet { checkPlay() }
    }

    // MARK: - Private
    private func loadImageIfNeeded(oldValue: String?) {
        let trimmedOld = oldValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawName = imageName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            // Name cleared: stop and reset
            pauseAnimation()
            clearDynamicObjects()
            videoItem = nil
            return
        }

        let parser = enabledMemoryCache ? SVGAImageView.enableMemoryParser : SVGAImageView.sharedParser

        if rawName.hasPrefix("http://") || rawName.hasPrefix("https://") {
            // Skip if same URL to avoid repeated parsing
            if trimmedOld == rawName { return }
            guard let url = URL(string: rawName) else {
                parseCompleteBlock?(false)
                return
            }
            parser.parse(with: url) { [weak self] videoItem in
                guard let self else { return }
                self.videoItem = videoItem
                if self.autoPlay { self.startAnimation() }
                self.parseCompleteBlock?(true)
            } failureBlock: { [weak self] _ in
                self?.imageName = nil
                self?.parseCompleteBlock?(false)
            }
        } else {
            // Local resource by name (the parser will find .svga in bundle)
            parser.parse(withNamed: rawName, in: nil) { [weak self] videoItem in
                guard let self else { return }
                self.videoItem = videoItem
                if self.autoPlay { self.startAnimation() }
                self.parseCompleteBlock?(true)
            } failureBlock: { [weak self] _ in
                self?.imageName = nil
                self?.parseCompleteBlock?(false)
            }
        }
    }

    /// Check if it should be played automatically
    private func checkPlay() {
        let isValid = !(imageName?.isEmpty ?? true)
        guard isValid && autoPlay else { return }
        let isVisible = (window != nil) && (superview != nil) && !isHidden && alpha > 0.0
        if isVisible {
            startAnimation()
        } else {
            pauseAnimation()
        }
    }

    private func parentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }
}
