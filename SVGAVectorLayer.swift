import UIKit

@objcMembers
final class SVGAVectorLayer: CALayer {

    // Readonly for ObjC
    private(set) var frames: [SVGAVideoSpriteFrameEntity]
    private(set) var drawedFrame: Int = 0
    private var keepFrameCache: [Int: Int] = [:]

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
        resetKeepFrameCache()
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
            self.keepFrameCache = other.keepFrameCache
        } else {
            self.frames = []
        }
        super.init(layer: layer)
        configureDefaults()
    }

    // MARK: - Public

    func stepToFrame(_ frame: Int) {
        if frame < frames.count {
            drawFrame(frame)
        }
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

    private func resetKeepFrameCache() {
        var lastKeep = 0
        var cache: [Int: Int] = [:]
        for (idx, frameItem) in frames.enumerated() {
            if !isKeepFrame(frameItem) {
                lastKeep = idx
            } else {
                cache[idx] = lastKeep
            }
        }
        keepFrameCache = cache
    }

    private func isKeepFrame(_ frameItem: SVGAVideoSpriteFrameEntity) -> Bool {
        guard !frameItem.shapes.isEmpty else { return false }
        
        let firstShape = frameItem.shapes[0]
        
        if let dict = firstShape as? NSDictionary,
           let type = dict["type"] as? String {
            return type == "keep"
        }
        
        // Check for SVGAProtoShapeEntity type
        // SVGAProtoShapeEntity_ShapeType_Keep = 3
        if let protoShape = firstShape as? SVGAProtoShapeEntity {
            return protoShape.type.rawValue == 3
        }
        
        return false
    }

    private func requestKeepFrame(_ frame: Int) -> Int {
        return keepFrameCache[frame] ?? Int.max
    }

    private func drawFrame(_ frame: Int) {
        guard frame < frames.count else { return }
        
        let frameItem = frames[frame]
        
        if isKeepFrame(frameItem) {
            if drawedFrame == requestKeepFrame(frame) {
                return
            }
        }
        
        // Remove all existing sublayers
        while let first = sublayers?.first {
            first.removeFromSuperlayer()
        }
        
        // Create and add shape layers
        for shape in frameItem.shapes {
            if let dict = shape as? NSDictionary,
               let type = dict["type"] as? String {
                var layer: CALayer?
                switch type {
                case "shape":
                    layer = createCurveLayer(dict)
                case "ellipse":
                    layer = createEllipseLayer(dict)
                case "rect":
                    layer = createRectLayer(dict)
                default:
                    break
                }
                if let layer = layer {
                    addSublayer(layer)
                }
            } else if let protoShape = shape as? SVGAProtoShapeEntity {
                var layer: CALayer?
                // SVGAProtoShapeEntity_ShapeType_Shape = 0
                // SVGAProtoShapeEntity_ShapeType_Rect = 1
                // SVGAProtoShapeEntity_ShapeType_Ellipse = 2
                switch protoShape.type.rawValue {
                case 0: // Shape
                    layer = createCurveLayerWithProto(protoShape)
                case 2: // Ellipse
                    layer = createEllipseLayerWithProto(protoShape)
                case 1: // Rect
                    layer = createRectLayerWithProto(protoShape)
                default:
                    break
                }
                if let layer = layer {
                    addSublayer(layer)
                }
            }
        }
        
        drawedFrame = frame
    }

    // MARK: - Shape Creation

    private func createCurveLayer(_ shape: NSDictionary) -> CALayer {
        let bezierPath = SVGABezierPath()
        if let args = shape["args"] as? NSDictionary,
           let d = args["d"] as? String {
            bezierPath.setValues(d)
        }
        let shapeLayer = bezierPath.createLayer()
        resetStyles(shapeLayer, shape: shape)
        resetTransform(shapeLayer, shape: shape)
        return shapeLayer
    }

    private func createCurveLayerWithProto(_ shape: SVGAProtoShapeEntity) -> CALayer {
        let bezierPath = SVGABezierPath()
        // SVGAProtoShapeEntity_Args_OneOfCase_Shape = 2
        if shape.argsOneOfCase.rawValue == 2 {
            let d = shape.shape.d
            if d is String && (d as! String).count > 0 {
                bezierPath.setValues(d as! String)
            }
        }
        let shapeLayer = bezierPath.createLayer()
        resetStyles(shapeLayer, protoShape: shape)
        resetTransform(shapeLayer, protoShape: shape)
        return shapeLayer
    }

    private func createEllipseLayer(_ shape: NSDictionary) -> CALayer {
        var bezierPath: UIBezierPath?
        if let args = shape["args"] as? NSDictionary,
           let x = args["x"] as? NSNumber,
           let y = args["y"] as? NSNumber,
           let radiusX = args["radiusX"] as? NSNumber,
           let radiusY = args["radiusY"] as? NSNumber {
            let cx = CGFloat(x.floatValue)
            let cy = CGFloat(y.floatValue)
            let rx = CGFloat(radiusX.floatValue)
            let ry = CGFloat(radiusY.floatValue)
            bezierPath = UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }
        
        if let path = bezierPath {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            resetStyles(shapeLayer, shape: shape)
            resetTransform(shapeLayer, shape: shape)
            return shapeLayer
        } else {
            return CALayer()
        }
    }

    private func createEllipseLayerWithProto(_ shape: SVGAProtoShapeEntity) -> CALayer {
        var bezierPath: UIBezierPath?
        // SVGAProtoShapeEntity_Args_OneOfCase_Ellipse = 4
        if shape.argsOneOfCase.rawValue == 4 {
            guard let ellipse = shape.ellipse else { return CALayer() }
            bezierPath = UIBezierPath(ovalIn: CGRect(x: CGFloat(ellipse.x) - CGFloat(ellipse.radiusX),
                                                      y: CGFloat(ellipse.y) - CGFloat(ellipse.radiusY),
                                                      width: CGFloat(ellipse.radiusX) * 2,
                                                      height: CGFloat(ellipse.radiusY) * 2))
        }
        
        if let path = bezierPath {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            resetStyles(shapeLayer, protoShape: shape)
            resetTransform(shapeLayer, protoShape: shape)
            return shapeLayer
        } else {
            return CALayer()
        }
    }

    private func createRectLayer(_ shape: NSDictionary) -> CALayer {
        var bezierPath: UIBezierPath?
        if let args = shape["args"] as? NSDictionary,
           let x = args["x"] as? NSNumber,
           let y = args["y"] as? NSNumber,
           let width = args["width"] as? NSNumber,
           let height = args["height"] as? NSNumber,
           let cornerRadius = args["cornerRadius"] as? NSNumber {
            let rect = CGRect(x: CGFloat(x.floatValue),
                             y: CGFloat(y.floatValue),
                             width: CGFloat(width.floatValue),
                             height: CGFloat(height.floatValue))
            bezierPath = UIBezierPath(roundedRect: rect, cornerRadius: CGFloat(cornerRadius.floatValue))
        }
        
        if let path = bezierPath {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            resetStyles(shapeLayer, shape: shape)
            resetTransform(shapeLayer, shape: shape)
            return shapeLayer
        } else {
            return CALayer()
        }
    }

    private func createRectLayerWithProto(_ shape: SVGAProtoShapeEntity) -> CALayer {
        var bezierPath: UIBezierPath?
        // SVGAProtoShapeEntity_Args_OneOfCase_Rect = 3
        if shape.argsOneOfCase.rawValue == 3 {
            guard let rect = shape.rect else { return CALayer() }
            bezierPath = UIBezierPath(roundedRect: CGRect(x: CGFloat(rect.x),
                                                          y: CGFloat(rect.y),
                                                          width: CGFloat(rect.width),
                                                          height: CGFloat(rect.height)),
                                     cornerRadius: CGFloat(rect.cornerRadius))
        }
        
        if let path = bezierPath {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            resetStyles(shapeLayer, protoShape: shape)
            resetTransform(shapeLayer, protoShape: shape)
            return shapeLayer
        } else {
            return CALayer()
        }
    }

    // MARK: - Style and Transform

    private func resetStyles(_ shapeLayer: CAShapeLayer, shape: NSDictionary) {
        shapeLayer.masksToBounds = false
        shapeLayer.backgroundColor = UIColor.clear.cgColor
        
        guard let styles = shape["styles"] as? NSDictionary else { return }
        
        // Fill color
        if let fill = styles["fill"] as? NSArray, fill.count == 4,
           let r = fill[0] as? NSNumber,
           let g = fill[1] as? NSNumber,
           let b = fill[2] as? NSNumber,
           let a = fill[3] as? NSNumber {
            shapeLayer.fillColor = UIColor(red: CGFloat(r.floatValue),
                                          green: CGFloat(g.floatValue),
                                          blue: CGFloat(b.floatValue),
                                          alpha: CGFloat(a.floatValue)).cgColor
        } else {
            shapeLayer.fillColor = UIColor.clear.cgColor
        }
        
        // Stroke color
        if let stroke = styles["stroke"] as? NSArray, stroke.count == 4,
           let r = stroke[0] as? NSNumber,
           let g = stroke[1] as? NSNumber,
           let b = stroke[2] as? NSNumber,
           let a = stroke[3] as? NSNumber {
            shapeLayer.strokeColor = UIColor(red: CGFloat(r.floatValue),
                                            green: CGFloat(g.floatValue),
                                            blue: CGFloat(b.floatValue),
                                            alpha: CGFloat(a.floatValue)).cgColor
        }
        
        // Stroke width
        if let strokeWidth = styles["strokeWidth"] as? NSNumber {
            shapeLayer.lineWidth = CGFloat(strokeWidth.floatValue)
        }
        
        // Line cap
        if let lineCapStr = styles["lineCap"] as? String {
            shapeLayer.lineCap = CAShapeLayerLineCap(rawValue: lineCapStr)
        }
        
        // Line join
        if let lineJoinStr = styles["lineJoin"] as? String {
            shapeLayer.lineJoin = CAShapeLayerLineJoin(rawValue: lineJoinStr)
        }
        
        // Line dash
        if let lineDash = styles["lineDash"] as? NSArray {
            var accept = true
            for obj in lineDash {
                if !(obj is NSNumber) {
                    accept = false
                    break
                }
            }
            if accept && lineDash.count == 3,
               let dash0 = lineDash[0] as? NSNumber,
               let dash1 = lineDash[1] as? NSNumber,
               let dash2 = lineDash[2] as? NSNumber {
                shapeLayer.lineDashPhase = CGFloat(dash2.floatValue)
                let val0 = dash0.floatValue < 1.0 ? 1.0 : dash0.floatValue
                let val1 = dash1.floatValue < 0.1 ? 0.1 : dash1.floatValue
                shapeLayer.lineDashPattern = [NSNumber(value: val0), NSNumber(value: val1)]
            }
        }
        
        // Miter limit
        if let miterLimit = styles["miterLimit"] as? NSNumber {
            shapeLayer.miterLimit = CGFloat(miterLimit.floatValue)
        }
    }

    private func resetStyles(_ shapeLayer: CAShapeLayer, protoShape: SVGAProtoShapeEntity) {
        shapeLayer.masksToBounds = false
        shapeLayer.backgroundColor = UIColor.clear.cgColor
        
        guard protoShape.hasStyles, let styles = protoShape.styles else { return }
        
        // Fill color
        if styles.hasFill {
            shapeLayer.fillColor = UIColor(red: CGFloat(styles.fill.r),
                                          green: CGFloat(styles.fill.g),
                                          blue: CGFloat(styles.fill.b),
                                          alpha: CGFloat(styles.fill.a)).cgColor
        } else {
            shapeLayer.fillColor = UIColor.clear.cgColor
        }
        
        // Stroke color
        if styles.hasStroke {
            shapeLayer.strokeColor = UIColor(red: CGFloat(styles.stroke.r),
                                            green: CGFloat(styles.stroke.g),
                                            blue: CGFloat(styles.stroke.b),
                                            alpha: CGFloat(styles.stroke.a)).cgColor
        }
        
        // Stroke width
        shapeLayer.lineWidth = CGFloat(styles.strokeWidth)
        
        // Line cap
        // SVGAProtoShapeEntity_ShapeStyle_LineCap_LineCapButt = 0
        // SVGAProtoShapeEntity_ShapeStyle_LineCap_LineCapRound = 1
        // SVGAProtoShapeEntity_ShapeStyle_LineCap_LineCapSquare = 2
        switch styles.lineCap.rawValue {
        case 0: // LineCapButt
            shapeLayer.lineCap = .butt
        case 1: // LineCapRound
            shapeLayer.lineCap = .round
        case 2: // LineCapSquare
            shapeLayer.lineCap = .square
        default:
            break
        }
        
        // Line join
        // SVGAProtoShapeEntity_ShapeStyle_LineJoin_LineJoinMiter = 0
        // SVGAProtoShapeEntity_ShapeStyle_LineJoin_LineJoinRound = 1
        // SVGAProtoShapeEntity_ShapeStyle_LineJoin_LineJoinBevel = 2
        switch styles.lineJoin.rawValue {
        case 1: // LineJoinRound
            shapeLayer.lineJoin = .round
        case 0: // LineJoinMiter
            shapeLayer.lineJoin = .miter
        case 2: // LineJoinBevel
            shapeLayer.lineJoin = .bevel
        default:
            break
        }
        
        // Line dash
        shapeLayer.lineDashPhase = CGFloat(styles.lineDashIii)
        let dashI = styles.lineDashI < 1.0 ? 1.0 : styles.lineDashI
        let dashIi = styles.lineDashIi < 0.1 ? 0.1 : styles.lineDashIi
        shapeLayer.lineDashPattern = [NSNumber(value: dashI), NSNumber(value: dashIi)]
        
        // Miter limit
        shapeLayer.miterLimit = CGFloat(styles.miterLimit)
    }

    private func resetTransform(_ shapeLayer: CAShapeLayer, shape: NSDictionary) {
        guard let transform = shape["transform"] as? NSDictionary,
              let a = transform["a"] as? NSNumber,
              let b = transform["b"] as? NSNumber,
              let c = transform["c"] as? NSNumber,
              let d = transform["d"] as? NSNumber,
              let tx = transform["tx"] as? NSNumber,
              let ty = transform["ty"] as? NSNumber else {
            return
        }
        
        let affine = CGAffineTransform(a: CGFloat(a.floatValue),
                                      b: CGFloat(b.floatValue),
                                      c: CGFloat(c.floatValue),
                                      d: CGFloat(d.floatValue),
                                      tx: CGFloat(tx.floatValue),
                                      ty: CGFloat(ty.floatValue))
        shapeLayer.transform = CATransform3DMakeAffineTransform(affine)
    }

    private func resetTransform(_ shapeLayer: CAShapeLayer, protoShape: SVGAProtoShapeEntity) {
        guard protoShape.hasTransform, let t = protoShape.transform else { return }
        
        let affine = CGAffineTransform(a: CGFloat(t.a),
                                      b: CGFloat(t.b),
                                      c: CGFloat(t.c),
                                      d: CGFloat(t.d),
                                      tx: CGFloat(t.tx),
                                      ty: CGFloat(t.ty))
        shapeLayer.transform = CATransform3DMakeAffineTransform(affine)
    }
}
