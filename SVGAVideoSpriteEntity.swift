import Foundation
import UIKit

@objcMembers
final class SVGAVideoSpriteEntity: NSObject {

    // MARK: - Public (ObjC-friendly)
    private(set) var imageKey: String?
    private(set) var frames: [SVGAVideoSpriteFrameEntity] = []
    private(set) var matteKey: String?

    // MARK: - Inits

    /// Exposed to ObjC as: - (instancetype)initWithJSONObject:(NSDictionary *)JSONObject;
    @objc(initWithJSONObject:)
    init(JSONObject: NSDictionary) {
        super.init()
        guard let dict = JSONObject as? [String: Any] else { return }

        if let key = dict["imageKey"] as? String {
            self.imageKey = key
        }
        if let matte = dict["matteKey"] as? String {
            self.matteKey = matte
        }
        if let jsonFrames = dict["frames"] as? [Any] {
            var list: [SVGAVideoSpriteFrameEntity] = []
            for item in jsonFrames {
                if let frameDict = item as? NSDictionary {
                    list.append(SVGAVideoSpriteFrameEntity(JSONObject: frameDict))
                }
            }
            self.frames = list
        }
    }

    /// Exposed to ObjC as: - (instancetype)initWithProtoObject:(SVGAProtoSpriteEntity *)protoObject;
    @objc(initWithProtoObject:)
    init(protoObject: SVGAProtoSpriteEntity) {
        super.init()
        self.imageKey = protoObject.imageKey
        self.matteKey = protoObject.matteKey

        var list: [SVGAVideoSpriteFrameEntity] = []
        for anyObj in protoObject.framesArray {
            if let frame = anyObj as? SVGAProtoFrameEntity {
                list.append(SVGAVideoSpriteFrameEntity(protoObject: frame))
            }
        }
        self.frames = list
    }

    // MARK: - Layer Factory

    /// Create content layer for this sprite.
    /// - Note: Returns optional to align with Swift call sites.
    func requestLayer(withBitmap bitmap: UIImage?) -> SVGAContentLayer? {
        let layer = SVGAContentLayer(frames: self.frames)
        // Optionally pass through imageKey if needed by dynamic logic
        layer.imageKey = self.imageKey

        if let bmp = bitmap {
            let bmpLayer = SVGABitmapLayer(frames: self.frames)
            bmpLayer.contents = bmp.cgImage
            layer.bitmapLayer = bmpLayer
        }

        layer.vectorLayer = SVGAVectorLayer(frames: self.frames)
        return layer
    }
}
