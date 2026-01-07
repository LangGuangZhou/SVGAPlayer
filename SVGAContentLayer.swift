import UIKit

@objcMembers
class SVGAContentLayer: CALayer {

    // MARK: - Public Properties

    var imageKey: String?
    var dynamicHidden: Bool = false {
        didSet { isHidden = dynamicHidden }
    }
    var dynamicDrawingBlock: SVGAPlayerDynamicDrawingBlock?

    var bitmapLayer: SVGABitmapLayer? {
        didSet {
            if oldValue !== bitmapLayer {
                oldValue?.removeFromSuperlayer()
                if let layer = bitmapLayer {
                    addSublayer(layer)
                    layer.frame = bounds
                }
            }
        }
    }

    var vectorLayer: SVGAVectorLayer? {
        didSet {
            if oldValue !== vectorLayer {
                oldValue?.removeFromSuperlayer()
                if let layer = vectorLayer {
                    addSublayer(layer)
                    layer.frame = bounds
                }
            }
        }
    }

    var textLayer: CATextLayer?

    // MARK: - Private

    private var frames: [SVGAVideoSpriteFrameEntity]

    // MARK: - Inits

    override init() {
        self.frames = []
        super.init()
        configureDefaults()
    }

    @objc(initWithFrames:)
    init(frames: [SVGAVideoSpriteFrameEntity]) {
        self.frames = frames
        super.init()
        configureDefaults()
        stepToFrame(0)
    }

    required init?(coder: NSCoder) {
        self.frames = []
        super.init(coder: coder)
        configureDefaults()
    }

    override init(layer: Any) {
        if let other = layer as? SVGAContentLayer {
            self.imageKey = other.imageKey
            self.dynamicHidden = other.dynamicHidden
            self.dynamicDrawingBlock = other.dynamicDrawingBlock
            self.bitmapLayer = other.bitmapLayer
            self.vectorLayer = other.vectorLayer
            self.textLayer = other.textLayer
            self.frames = other.frames
        } else {
            self.frames = []
        }
        super.init(layer: layer)
        configureDefaults()
    }

    private func configureDefaults() {
        backgroundColor = UIColor.clear.cgColor
        masksToBounds = false
    }

    // MARK: - Public

    func stepToFrame(_ frame: Int) {
        guard !dynamicHidden else { return }
        guard frame < frames.count else { return }

        let frameItem = frames[frame]
        if frameItem.alpha > 0.0 {
            isHidden = false
            opacity = Float(frameItem.alpha)

            position = CGPoint(x: 0, y: 0)
            transform = CATransform3DIdentity
            self.frame = frameItem.layout
            transform = CATransform3DMakeAffineTransform(frameItem.transform)

            var offsetX = self.frame.origin.x - frameItem.nx
            var offsetY = self.frame.origin.y - frameItem.ny
            if offsetX.isNaN { offsetX = 0 }
            if offsetY.isNaN { offsetY = 0 }
            position = CGPoint(x: position.x - offsetX, y: position.y - offsetY)

            mask = frameItem.maskLayer

            bitmapLayer?.stepToFrame(frame)
            vectorLayer?.stepToFrame(frame)
        } else {
            isHidden = true
        }

        dynamicDrawingBlock?(self, frame)
    }

    // MARK: - Layout

    override var frame: CGRect {
        didSet {
            bitmapLayer?.frame = bounds
            vectorLayer?.frame = bounds

            if let sublayers = sublayers {
                for sublayer in sublayers where sublayer is CATextLayer {
                    var f = sublayer.frame
                    f.origin.x = (self.frame.size.width - f.size.width) / 2.0
                    f.origin.y = (self.frame.size.height - f.size.height) / 2.0
                    sublayer.frame = f
                }
            }
        }
    }
}
