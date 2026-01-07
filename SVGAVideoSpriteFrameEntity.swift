import Foundation
import UIKit

@objcMembers
class SVGAVideoSpriteFrameEntity: NSObject {

    // MARK: - Public Properties (ObjC-friendly)

    private(set) var alpha: CGFloat = 0.0
    var transform: CGAffineTransform = .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    var layout: CGRect = .zero
    var nx: CGFloat = 0.0
    var ny: CGFloat = 0.0
    private(set) var shapes: [Any] = []

    /// Lazy-created mask layer from `clipPath`. Readonly for ObjC.
    var maskLayer: CALayer? {
        if cachedMaskLayer == nil, let path = clipPath, !path.isEmpty {
            let bezier = SVGABezierPath()
            bezier.setValues(path)
            cachedMaskLayer = bezier.createLayer()
        }
        return cachedMaskLayer
    }

    // MARK: - Private State

    private var previousFrame: SVGAVideoSpriteFrameEntity?
    private var clipPath: String?
    private var cachedMaskLayer: CALayer?

    // MARK: - Inits

    /// Exposed to ObjC as: - (instancetype)initWithJSONObject:(NSDictionary *)JSONObject;
    @objc(initWithJSONObject:)
    init(JSONObject: NSDictionary) {
        super.init()

        if let alphaNum = JSONObject["alpha"] as? NSNumber {
            alpha = CGFloat(alphaNum.floatValue)
        }

        if let layoutDict = JSONObject["layout"] as? NSDictionary,
           let x = layoutDict["x"] as? NSNumber,
           let y = layoutDict["y"] as? NSNumber,
           let width = layoutDict["width"] as? NSNumber,
           let height = layoutDict["height"] as? NSNumber {
            layout = CGRect(x: CGFloat(x.floatValue),
                            y: CGFloat(y.floatValue),
                            width: CGFloat(width.floatValue),
                            height: CGFloat(height.floatValue))
        }

        if let transformDict = JSONObject["transform"] as? NSDictionary,
           let a = transformDict["a"] as? NSNumber,
           let b = transformDict["b"] as? NSNumber,
           let c = transformDict["c"] as? NSNumber,
           let d = transformDict["d"] as? NSNumber,
           let tx = transformDict["tx"] as? NSNumber,
           let ty = transformDict["ty"] as? NSNumber {
            transform = CGAffineTransform(a: CGFloat(a.floatValue),
                                          b: CGFloat(b.floatValue),
                                          c: CGFloat(c.floatValue),
                                          d: CGFloat(d.floatValue),
                                          tx: CGFloat(tx.floatValue),
                                          ty: CGFloat(ty.floatValue))
        }

        if let clip = JSONObject["clipPath"] as? NSString {
            clipPath = clip as String
        }

        if let arr = JSONObject["shapes"] as? NSArray {
            shapes = arr as? [Any] ?? arr.map { $0 }
        }

        computeNXNY()
    }

    /// Exposed to ObjC as: - (instancetype)initWithProtoObject:(SVGAProtoFrameEntity *)protoObject;
    @objc(initWithProtoObject:)
    init(protoObject: SVGAProtoFrameEntity) {
        super.init()

        alpha = CGFloat(protoObject.alpha)

        if protoObject.hasLayout {
            layout = CGRect(x: CGFloat(protoObject.layout.x),
                            y: CGFloat(protoObject.layout.y),
                            width: CGFloat(protoObject.layout.width),
                            height: CGFloat(protoObject.layout.height))
        }

        if protoObject.hasTransform {
            transform = CGAffineTransform(a: CGFloat(protoObject.transform.a),
                                          b: CGFloat(protoObject.transform.b),
                                          c: CGFloat(protoObject.transform.c),
                                          d: CGFloat(protoObject.transform.d),
                                          tx: CGFloat(protoObject.transform.tx),
                                          ty: CGFloat(protoObject.transform.ty))
        }

        if !protoObject.clipPath.isEmpty {
            clipPath = protoObject.clipPath
        }

        if let arr = protoObject.shapesArray {
            shapes = arr as? [Any] ?? arr.map { $0 }
        }

        computeNXNY()
    }

    // MARK: - Helpers

    private func computeNXNY() {
        let x = layout.origin.x
        let y = layout.origin.y
        let w = layout.size.width
        let h = layout.size.height

        let llx = transform.a * x + transform.c * y + transform.tx
        let lrx = transform.a * (x + w) + transform.c * y + transform.tx
        let lbx = transform.a * x + transform.c * (y + h) + transform.tx
        let rbx = transform.a * (x + w) + transform.c * (y + h) + transform.tx

        let lly = transform.b * x + transform.d * y + transform.ty
        let lry = transform.b * (x + w) + transform.d * y + transform.ty
        let lby = transform.b * x + transform.d * (y + h) + transform.ty
        let rby = transform.b * (x + w) + transform.d * (y + h) + transform.ty

        nx = min(min(lbx, rbx), min(llx, lrx))
        ny = min(min(lby, rby), min(lly, lry))
    }
}
