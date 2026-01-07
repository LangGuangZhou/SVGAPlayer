import Foundation

@objcMembers
final class SVGAAudioEntity: NSObject {

    // MARK: - Public Properties

    /// Readonly in Swift/ObjC
    let audioKey: String
    let startFrame: Int
    let endFrame: Int
    let startTime: Int

    // MARK: - Initializer

    /// Exposed to ObjC as: - (instancetype)initWithProtoObject:(SVGAProtoAudioEntity *)protoObject;
    @objc
    init(protoObject: SVGAProtoAudioEntity) {
        self.audioKey = protoObject.audioKey
        self.startFrame = Int(protoObject.startFrame)
        self.endFrame = Int(protoObject.endFrame)
        self.startTime = Int(protoObject.startTime)
        super.init()
    }
}
