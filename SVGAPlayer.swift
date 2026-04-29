import UIKit

//@protocol SVGAPlayerDelegate <NSObject>
//
//@optional
//- (void)svgaPlayerDidFinishedAnimation:(SVGAPlayer *)player;
//- (void)svgaPlayerDidAnimatedToFrame:(NSInteger)frame player:(SVGAPlayer *)player;
//- (void)svgaPlayerDidAnimatedToPercentage:(CGFloat)percentage;
//
//@end

@objc public protocol SVGAPlayerDelegate: NSObjectProtocol {
    @objc optional func svgaPlayerDidFinishedAnimation(_ player: SVGAPlayer)
    @objc optional func svgaPlayerDidAnimatedToFrame(_ frame: Int, player: SVGAPlayer)
    @objc optional func svgaPlayerDidAnimatedToPercentage(_ percentage: CGFloat)
}

public typealias SVGAPlayerDynamicDrawingBlock = @convention(block) (_ layer: CALayer, _ frame: Int) -> Void

/// Weak proxy to break CADisplayLink -> SVGAPlayer retain cycle
private class _SVGADisplayLinkProxy {
    weak var target: SVGAPlayer?
    init(_ target: SVGAPlayer) { self.target = target }
    @objc func tick() { target?.svgaDisplayLinkTick() }
}

@objcMembers
open class SVGAPlayer: UIView {
    // MARK: - Public

    public var videoItem: SVGAVideoEntity? {
        didSet {
            currentRange = NSRange(location: 0, length: videoItem?.frames ?? 0)
            reversing = false
            currentFrame = 0
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.clear()
                self.draw()
            }
        }
    }

    public var clearsAfterStop: Bool = true
    public var loops: Int = 0
    public var fillMode: String = ""

    public weak var delegate: SVGAPlayerDelegate?
    public var finishAnimation: (() -> Void)?

    // Dynamic
    private(set) var dynamicObjects: [String: UIImage] = [:]
    private(set) var dynamicTexts: [String: NSAttributedString] = [:]
    private(set) var dynamicDrawings: [String: SVGAPlayerDynamicDrawingBlock] = [:]
    private(set) var dynamicHiddens: [String: Bool] = [:]

    // MARK: - Private

    private var drawLayer: CALayer = CALayer()
    private var audioLayers: [SVGAAudioLayer] = []
    private var displayLink: CADisplayLink?
    private var currentFrame: Int = 0
    private var contentLayers: [SVGAContentLayer] = []
    private var loopCount: Int = 0
    private var currentRange: NSRange = NSRange(location: 0, length: 0)
    private var forwardAnimating: Bool = false
    private var reversing: Bool = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .top
        clearsAfterStop = true
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        contentMode = .top
        clearsAfterStop = true
    }

    deinit {
        displayLink?.invalidate()
        displayLink = nil
        clearAudios()
    }

    // MARK: - Control

    public func startAnimation() {
        startAnimation(resetLoopCount: true)
    }

    private func startAnimation(resetLoopCount: Bool) {
        guard let video = videoItem else {
            NSLog("videoItem could not be nil!")
            return
        }
        stopAnimation(false)
        if resetLoopCount {
            loopCount = 0
        }
        displayLink?.invalidate()
        let proxy = _SVGADisplayLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(_SVGADisplayLinkProxy.tick))
        link.preferredFramesPerSecond = video.FPS
        link.add(to: .main, forMode: .common)
        displayLink = link
        forwardAnimating = !reversing
    }

    /// Resume from pause without resetting loopCount
    public func resumeAnimation() {
        startAnimation(resetLoopCount: false)
    }

    @objc(startAnimationWithRange:reverse:)
    public func startAnimation(range: NSRange, reverse: Bool) {
        currentRange = range
        reversing = reverse
        if reverse {
            currentFrame = min((videoItem?.frames ?? 0) - 1, range.location + range.length - 1)
        } else {
            currentFrame = max(0, range.location)
        }
        startAnimation()
    }

    public func pauseAnimation() {
        stopAnimation(false)
    }

    public func stopAnimation() {
        stopAnimation(clearsAfterStop)
    }

    public func stopAnimation(_ isClear: Bool) {
        forwardAnimating = false
        displayLink?.invalidate()
        if isClear {
            clear()
        }
        clearAudios()
        displayLink = nil
    }

    public func clear() {
        contentLayers.removeAll()
        drawLayer.removeFromSuperlayer()
    }

    private func clearAudios() {
        for layer in audioLayers {
            layer.audioPlayer?.stop()
        }
    }

    // MARK: - Seek

    @objc(stepToFrame:andPlay:)
    public func stepToFrame(_ frame: Int, andPlay: Bool) {
        guard let video = videoItem, frame >= 0, frame < video.frames else { return }
        pauseAnimation()
        currentFrame = frame
        update()
        if andPlay {
            let proxy = _SVGADisplayLinkProxy(self)
            let link = CADisplayLink(target: proxy, selector: #selector(_SVGADisplayLinkProxy.tick))
            link.preferredFramesPerSecond = video.FPS
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc(stepToPercentage:andPlay:)
    public func stepToPercentage(_ percentage: CGFloat, andPlay: Bool) {
        guard let video = videoItem else { return }
        var frame = Int(CGFloat(video.frames) * percentage)
        if frame >= video.frames && frame > 0 {
            frame = video.frames - 1
        }
        stepToFrame(frame, andPlay: andPlay)
    }

    // MARK: - Build Layers

    public func draw() {
        guard let video = videoItem else { return }
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: video.videoSize.width, height: video.videoSize.height)
        root.masksToBounds = true

        var tempHostLayers: [String: CALayer] = [:]
        var tempContentLayers: [SVGAContentLayer] = []

        for (idx, sprite) in video.sprites.enumerated() {
            var bitmap: UIImage?
            if let imgKey = sprite.imageKey {
                let bitmapKey = (imgKey as NSString).deletingPathExtension
                bitmap = dynamicObjects[bitmapKey] ?? video.images[bitmapKey]
            }

            guard let contentLayer = sprite.requestLayer(withBitmap: bitmap) else { continue }
            contentLayer.imageKey = sprite.imageKey
            tempContentLayers.append(contentLayer)

            if let imageKey = sprite.imageKey, imageKey.hasSuffix(".matte") {
                let host = CALayer()
                host.mask = contentLayer
                tempHostLayers[imageKey] = host
            } else {
                if let matteKey = sprite.matteKey, !matteKey.isEmpty {
                    if let host = tempHostLayers[matteKey] {
                        host.addSublayer(contentLayer)
                        // Check if this is the first sprite with this matteKey
                        // Match Objective-C logic: add hostLayer when matteKey differs from previous sprite
                        let shouldAddHost: Bool
                        if idx == 0 {
                            shouldAddHost = true
                        } else {
                            let prevMatteKey = video.sprites[idx - 1].matteKey
                            shouldAddHost = matteKey != prevMatteKey
                        }
                        if shouldAddHost {
                            root.addSublayer(host)
                        }
                    }
                    // Note: If hostLayer doesn't exist, contentLayer won't be added anywhere
                    // This matches Objective-C behavior where nil hostLayer operations are no-ops
                } else {
                    root.addSublayer(contentLayer)
                }
            }

            if let key = sprite.imageKey {
                if let text = dynamicTexts[key] {
                    let size = text.boundingRect(with: CGSizeMake( .greatestFiniteMagnitude, .greatestFiniteMagnitude),
                                                 options: .usesLineFragmentOrigin, context: nil).size
                    let textLayer = CATextLayer()
                    textLayer.contentsScale = UIScreen.main.scale
                    textLayer.string = text
                    textLayer.frame = CGRect(origin: .zero, size: size)
                    contentLayer.addSublayer(textLayer)
                    contentLayer.textLayer = textLayer
                }
                if let hidden = dynamicHiddens[key], hidden {
                    contentLayer.dynamicHidden = true
                }
                if let drawing = dynamicDrawings[key] {
                    contentLayer.dynamicDrawingBlock = drawing
                }
            }
        }

        contentLayers = tempContentLayers
        layer.addSublayer(root)
        drawLayer = root

        var audios: [SVGAAudioLayer] = []
        for audio in video.audios {
            let audioLayer = SVGAAudioLayer(audioItem: audio, videoItem: video)
            audios.append(audioLayer)
        }
        audioLayers = audios

        update()
        resize()
    }

    // MARK: - Layout

    public func resize() {
        guard let video = videoItem else { return }
        switch contentMode {
        case .scaleAspectFit:
            let videoRatio = video.videoSize.width / video.videoSize.height
            let layerRatio = bounds.size.width / bounds.size.height
            if videoRatio > layerRatio {
                let ratio = bounds.size.width / video.videoSize.width
                let offset = CGPoint(x: (1.0 - ratio) / 2.0 * video.videoSize.width,
                                     y: (1.0 - ratio) / 2.0 * video.videoSize.height
                                     - (bounds.size.height - video.videoSize.height * ratio) / 2.0)
                drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: -offset.x, ty: -offset.y))
            } else {
                let ratio = bounds.size.height / video.videoSize.height
                let offset = CGPoint(x: (1.0 - ratio) / 2.0 * video.videoSize.width - (bounds.size.width - video.videoSize.width * ratio) / 2.0,
                                     y: (1.0 - ratio) / 2.0 * video.videoSize.height)
                drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: -offset.x, ty: -offset.y))
            }
        case .scaleAspectFill:
            let videoRatio = video.videoSize.width / video.videoSize.height
            let layerRatio = bounds.size.width / bounds.size.height
            if videoRatio < layerRatio {
                let ratio = bounds.size.width / video.videoSize.width
                let offset = CGPoint(x: (1.0 - ratio) / 2.0 * video.videoSize.width,
                                     y: (1.0 - ratio) / 2.0 * video.videoSize.height
                                     - (bounds.size.height - video.videoSize.height * ratio) / 2.0)
                drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: -offset.x, ty: -offset.y))
            } else {
                let ratio = bounds.size.height / video.videoSize.height
                let offset = CGPoint(x: (1.0 - ratio) / 2.0 * video.videoSize.width - (bounds.size.width - video.videoSize.width * ratio) / 2.0,
                                     y: (1.0 - ratio) / 2.0 * video.videoSize.height)
                drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: ratio, b: 0, c: 0, d: ratio, tx: -offset.x, ty: -offset.y))
            }
        case .top:
            let scaleX = bounds.size.width / video.videoSize.width
            let offset = CGPoint(x: (1.0 - scaleX) / 2.0 * video.videoSize.width,
                                 y: (1 - scaleX) / 2.0 * video.videoSize.height)
            drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleX, tx: -offset.x, ty: -offset.y))
        case .bottom:
            let scaleX = bounds.size.width / video.videoSize.width
            let offset = CGPoint(x: (1.0 - scaleX) / 2.0 * video.videoSize.width,
                                 y: (1.0 - scaleX) / 2.0 * video.videoSize.height)
            drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleX, tx: -offset.x, ty: -offset.y + bounds.size.height - video.videoSize.height * scaleX))
        case .left:
            let scaleY = bounds.size.height / video.videoSize.height
            let offset = CGPoint(x: (1.0 - scaleY) / 2.0 * video.videoSize.width,
                                 y: (1 - scaleY) / 2.0 * video.videoSize.height)
            drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: scaleY, b: 0, c: 0, d: scaleY, tx: -offset.x, ty: -offset.y))
        case .right:
            let scaleY = bounds.size.height / video.videoSize.height
            let offset = CGPoint(x: (1.0 - scaleY) / 2.0 * video.videoSize.width,
                                 y: (1.0 - scaleY) / 2.0 * video.videoSize.height)
            drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: scaleY, b: 0, c: 0, d: scaleY, tx: -offset.x + bounds.size.width - video.videoSize.width * scaleY, ty: -offset.y))
        default:
            let scaleX = bounds.size.width / video.videoSize.width
            let scaleY = bounds.size.height / video.videoSize.height
            let offset = CGPoint(x: (1.0 - scaleX) / 2.0 * video.videoSize.width,
                                 y: (1 - scaleY) / 2.0 * video.videoSize.height)
            drawLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: -offset.x, ty: -offset.y))
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        resize()
    }

    // MARK: - Tick

    func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in contentLayers {
            layer.stepToFrame(currentFrame)
        }
        CATransaction.setDisableActions(false)
        CATransaction.commit()

        if forwardAnimating && !audioLayers.isEmpty {
            for layer in audioLayers {
                if layer.audioItem.startFrame == currentFrame {
                    layer.audioPlayer?.currentTime = TimeInterval(Double(layer.audioItem.startTime) / 1000.0)
                    layer.audioPlayer?.play()
                } else if layer.audioItem.endFrame <= currentFrame {
                    layer.audioPlayer?.stop()
                }
            }
        }
    }

    // Bridge selector for CADisplayLink to avoid conflict with UIResponder.next
    @objc func svgaDisplayLinkTick() {
        next()
    }

    @objc func next() {
        guard let video = videoItem else { return }
        if reversing {
            currentFrame -= 1
            if currentFrame < max(0, currentRange.location) {
                currentFrame = min(video.frames - 1, currentRange.location + currentRange.length - 1)
                loopCount += 1
            }
        } else {
            currentFrame += 1
            if currentFrame >= min(video.frames, currentRange.location + currentRange.length) {
                currentFrame = max(0, currentRange.location)
                clearAudios()
                loopCount += 1
            }
        }

        if loops > 0 && loopCount >= loops {
            stopAnimation(false)
            clearAudios()
            if fillMode == "Backward" {
                currentFrame = max(0, currentRange.location)
                update()
            } else if fillMode == "Forward" {
                currentFrame = min(video.frames - 1, currentRange.location + currentRange.length - 1)
                update()
            } else if clearsAfterStop {
                clear()
            }

            delegate?.svgaPlayerDidFinishedAnimation?(self)
            finishAnimation?()
            return
        }

        update()

        delegate?.svgaPlayerDidAnimatedToFrame?(currentFrame, player: self)
        if video.frames > 0 {
            let p = CGFloat(currentFrame + 1) / CGFloat(video.frames)
            delegate?.svgaPlayerDidAnimatedToPercentage?(p)
        }
    }

    // MARK: - Dynamic API (ObjC compatible)

    @objc(setImage:forKey:)
    public func setImage(_ image: UIImage?, forKey key: String) {
        guard let image = image else { return }
        dynamicObjects[key] = image
        if !contentLayers.isEmpty {
            for layer in contentLayers where layer.isKind(of: SVGAContentLayer.self) && layer.imageKey == key {
                layer.bitmapLayer?.contents = image.cgImage
            }
        }
    }

    @objc(setImage:forKey:referenceLayer:)
    public func setImage(_ image: UIImage?, forKey key: String, referenceLayer: CALayer?) {
        setImage(image, forKey: key)
    }

    @objc(setAttributedText:forKey:)
    public func setAttributedText(_ attributedText: NSAttributedString?, forKey key: String) {
        guard let text = attributedText else { return }
        dynamicTexts[key] = text
        if !contentLayers.isEmpty {
            let size = text.boundingRect(with: CGSizeMake(.greatestFiniteMagnitude, .greatestFiniteMagnitude),
                                         options: .usesLineFragmentOrigin, context: nil).size
            var textLayer: CATextLayer?
            for layer in contentLayers where layer.isKind(of: SVGAContentLayer.self) && layer.imageKey == key {
                textLayer = layer.textLayer
                if textLayer == nil {
                    let tl = CATextLayer()
                    layer.addSublayer(tl)
                    layer.textLayer = tl
                    textLayer = tl
                }
            }
            if let tl = textLayer {
                tl.contentsScale = UIScreen.main.scale
                tl.string = text
                tl.frame = CGRect(origin: .zero, size: size)
            }
        }
    }

    @objc(setDrawingBlock:forKey:)
    public func setDrawingBlock(_ drawingBlock: SVGAPlayerDynamicDrawingBlock?, forKey key: String) {
        if let block = drawingBlock {
            dynamicDrawings[key] = block
        } else {
            dynamicDrawings.removeValue(forKey: key)
        }
        if !contentLayers.isEmpty {
            for layer in contentLayers where layer.isKind(of: SVGAContentLayer.self) && layer.imageKey == key {
                layer.dynamicDrawingBlock = drawingBlock
            }
        }
    }

    @objc(setHidden:forKey:)
    public func setHidden(_ hidden: Bool, forKey key: String) {
        dynamicHiddens[key] = hidden
        if !contentLayers.isEmpty {
            for layer in contentLayers where layer.isKind(of: SVGAContentLayer.self) && layer.imageKey == key {
                layer.dynamicHidden = hidden
            }
        }
    }

    public func clearDynamicObjects() {
        dynamicObjects.removeAll()
        dynamicTexts.removeAll()
        dynamicHiddens.removeAll()
        dynamicDrawings.removeAll()
    }
}
