import UIKit

@objcMembers
final class SVGABitmapLayer: CALayer {

    // Readonly for ObjC
    private(set) var frames: [SVGAVideoSpriteFrameEntity]
    private(set) var drawedFrame: Int = 0

    // MARK: - Inits

    override init() {
        self.frames = []
        super.init()
        configureDefaults()
    }

    /// Exposed to ObjC as: - (instancetype)initWithFrames:(NSArray<SVGAVideoSpriteFrameEntity *> *)frames;
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
        if let other = layer as? SVGABitmapLayer {
            self.frames = other.frames
            self.drawedFrame = other.drawedFrame
        } else {
            self.frames = []
        }
        super.init(layer: layer)
        configureDefaults()
    }

    // MARK: - Public

    /// Advance to specific frame index.
    /// Rendering logic will be implemented based on SVGAVideoSpriteFrameEntity details.
    func stepToFrame(_ frame: Int) {
        self.drawedFrame = max(0, frame)
        // TODO: Update `contents` / geometry from `frames[drawedFrame]` when frame model is available.
    }

    // MARK: - Private

    private func configureDefaults() {
        backgroundColor = UIColor.clear.cgColor
        masksToBounds = false
        contentsGravity = .resizeAspect
    }
}
