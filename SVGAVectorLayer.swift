import UIKit

@objcMembers
final class SVGAVectorLayer: CALayer {

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
        if let other = layer as? SVGAVectorLayer {
            self.frames = other.frames
            self.drawedFrame = other.drawedFrame
        } else {
            self.frames = []
        }
        super.init(layer: layer)
        configureDefaults()
    }

    // MARK: - Public

    /// Advance to specific frame index and update vector contents.
    /// Rendering logic will be implemented based on `SVGAVideoSpriteFrameEntity.shapes`.
    func stepToFrame(_ frame: Int) {
        self.drawedFrame = max(0, frame)
        guard frame < frames.count else {
            isHidden = true
            return
        }
        isHidden = false

        // TODO:
        // 1) Read `frames[frame].shapes`.
        // 2) Build CAShapeLayer(s) by SVG path data (via `SVGABezierPath`) or other shape types.
        // 3) Apply fill/stroke/line attributes and add as sublayers.
        // 4) Reuse sublayers for performance if needed.
    }

    // MARK: - Private

    private func configureDefaults() {
        backgroundColor = UIColor.clear.cgColor
        isOpaque = false
        masksToBounds = false
        contentsScale = UIScreen.main.scale
        allowsEdgeAntialiasing = true
        edgeAntialiasingMask = [.layerLeftEdge, .layerRightEdge, .layerBottomEdge, .layerTopEdge]
    }
}
