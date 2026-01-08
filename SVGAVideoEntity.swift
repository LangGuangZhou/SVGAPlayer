import Foundation
import UIKit


@objcMembers
final class _FCWeakContainer: NSObject {
    weak var object: SVGAVideoEntity?
    lazy var vcs: NSHashTable<UIViewController> = {
        NSHashTable<UIViewController>.weakObjects()
    }()
}

@objcMembers
public final class SVGAVideoEntity: NSObject {

    // MARK: - Public Properties

    var videoSize: CGSize = CGSize(width: 100, height: 100)
    private(set) var FPS: Int = 20
    public private(set) var frames: Int = 0
    private(set) var images: [String: UIImage] = [:]
    private(set) var audiosData: [String: Data] = [:]
    private(set) var sprites: [SVGAVideoSpriteEntity] = []
    private(set) var audios: [SVGAAudioEntity] = []

    // MARK: - Private

    private var cacheDir: String = ""

    // MARK: - Cache (Static)

    private static let videoCache: NSCache<NSString, _FCWeakContainer> = {
        let c = NSCache<NSString, _FCWeakContainer>()
        return c
    }()

    private static var cacheKeys = Set<String>()

    // MARK: - Inits

    /// Exposed to ObjC as: - (instancetype)initWithJSONObject:(NSDictionary *)JSONObject cacheDir:(NSString *)cacheDir;
    @objc(initWithJSONObject:cacheDir:)
    init(JSONObject: NSDictionary, cacheDir: String) {
        super.init()
        self.cacheDir = cacheDir
        self.images = [:]
        resetMovieWithJSONObject(JSONObject as? [String: Any] ?? [:])
    }

    /// Exposed to ObjC as: - (instancetype)initWithProtoObject:(SVGAProtoMovieEntity *)protoObject cacheDir:(NSString *)cacheDir;
    @objc(initWithProtoObject:cacheDir:)
    init(protoObject: SVGAProtoMovieEntity, cacheDir: String) {
        super.init()
        self.cacheDir = cacheDir
        self.images = [:]
        resetMovieWithProtoObject(protoObject)
    }

    // MARK: - Reset From JSON

    @objc(resetImagesWithJSONObject:)
    func resetImages(withJSONObject JSONObject: NSDictionary) {
        guard let dict = JSONObject as? [String: Any] else { return }
        var result: [String: UIImage] = [:]

        if let jsonImages = dict["images"] as? [String: String] {
            for (key, obj) in jsonImages {
                let filePath = (cacheDir as NSString).appendingPathComponent("\(obj).png")
                if let imageData = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                   let image = UIImage(data: imageData, scale: 2.0) {
                    let plainKey = (key as NSString).deletingPathExtension
                    result[plainKey] = image
                }
            }
        }
        self.images = result
    }

    @objc(resetSpritesWithJSONObject:)
    func resetSprites(withJSONObject JSONObject: NSDictionary) {
        guard let dict = JSONObject as? [String: Any] else { return }
        var result: [SVGAVideoSpriteEntity] = []

        if let jsonSprites = dict["sprites"] as? [Any] {
            for item in jsonSprites {
                if let sp = item as? NSDictionary {
                    let entity = SVGAVideoSpriteEntity(JSONObject: sp)
                    result.append(entity)
                }
            }
        }
        self.sprites = result
    }

    // MARK: - Reset From Proto

    @objc(resetImagesWithProtoObject:)
    func resetImages(withProtoObject protoObject: SVGAProtoMovieEntity) {
        var imgs: [String: UIImage] = [:]
        var audios: [String: Data] = [:]

        let protoImages: [String: Any] = (protoObject.images as? [String: Any]) ?? [:]
        for (key, anyVal) in protoImages {
            if let data = anyVal as? Data, let fileName = String(data: data, encoding: .utf8) {
                // Try "cacheDir/fileName.png"
                var filePath = (cacheDir as NSString).appendingPathComponent("\(fileName).png")
                if !FileManager.default.fileExists(atPath: filePath) {
                    // Fallback "cacheDir/fileName"
                    filePath = (cacheDir as NSString).appendingPathComponent(fileName)
                }
                if FileManager.default.fileExists(atPath: filePath),
                   let imageData = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                   let image = UIImage(data: imageData, scale: 2.0) {
                    imgs[key] = image
                }
            } else if let raw = anyVal as? Data {
                if Self.isMP3Data(raw) {
                    audios[key] = raw
                } else if let image = UIImage(data: raw, scale: 2.0) {
                    imgs[key] = image
                }
            }
        }

        self.images = imgs
        self.audiosData = audios
    }

    @objc(resetSpritesWithProtoObject:)
    func resetSprites(withProtoObject protoObject: SVGAProtoMovieEntity) {
        var result: [SVGAVideoSpriteEntity] = []
        for anyObj in protoObject.spritesArray {
            if let sp = anyObj as? SVGAProtoSpriteEntity {
                result.append(SVGAVideoSpriteEntity(protoObject: sp))
            }
        }
        self.sprites = result
    }

    @objc(resetAudiosWithProtoObject:)
    func resetAudios(withProtoObject protoObject: SVGAProtoMovieEntity) {
        var result: [SVGAAudioEntity] = []
        for anyObj in protoObject.audiosArray {
            if let au = anyObj as? SVGAProtoAudioEntity {
                result.append(SVGAAudioEntity(protoObject: au))
            }
        }
        self.audios = result
    }

    // MARK: - Cache APIs

    @objc(readCache:)
    class func readCache(_ cacheKey: String) -> SVGAVideoEntity? {
        return readCache(cacheKey, vc: nil)
    }

    @objc(readCache:vc:)
    class func readCache(_ cacheKey: String, vc: UIViewController?) -> SVGAVideoEntity? {
        guard let container = videoCache.object(forKey: cacheKey as NSString) else { return nil }
        if let vc = vc {
            if !container.vcs.allObjects.contains(where: { $0 === vc }) {
                container.vcs.add(vc)
            }
        }
        return container.object
    }

    @objc(saveCache:)
    func saveCache(_ cacheKey: String) {
        saveCache(cacheKey, vc: nil)
    }

    @objc(saveCache:vc:)
    func saveCache(_ cacheKey: String, vc: UIViewController?) {
        let container = _FCWeakContainer()
        container.object = self
        if let vc = vc, !container.vcs.allObjects.contains(where: { $0 === vc }) {
            container.vcs.add(vc)
        }
        if !Self.cacheKeys.contains(cacheKey) {
            Self.cacheKeys.insert(cacheKey)
        }
        Self.videoCache.setObject(container, forKey: cacheKey as NSString)
    }

    @objc(removeCache:)
    class func removeCache(_ cacheKey: String) {
        videoCache.removeObject(forKey: cacheKey as NSString)
    }

    @objc(removeAllCaches)
    class func removeAllCaches() {
        videoCache.removeAllObjects()
    }

    @objc(releaseAllCaches)
    class func releaseAllCaches() {
        for ck in cacheKeys {
            if let container = videoCache.object(forKey: ck as NSString) {
                for vc in container.vcs.allObjects {
                    NSLog("[SVGAVideoEntity] %@ vc class = %@, vc: %@", ck, NSStringFromClass(type(of: vc)), vc.description)
                }
                if container.vcs.count == 0 {
                    removeCache(ck)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func resetMovieWithJSONObject(_ json: [String: Any]) {
        if let movie = json["movie"] as? [String: Any] {
            if let viewBox = movie["viewBox"] as? [String: Any],
               let width = viewBox["width"] as? NSNumber,
               let height = viewBox["height"] as? NSNumber {
                self.videoSize = CGSize(width: width.doubleValue, height: height.doubleValue)
            }
            if let fps = movie["fps"] as? NSNumber {
                self.FPS = fps.intValue
            }
            if let frames = movie["frames"] as? NSNumber {
                self.frames = frames.intValue
            }
        }
    }

    private func resetMovieWithProtoObject(_ proto: SVGAProtoMovieEntity) {
        if proto.hasParams {
            self.videoSize = CGSize(width: CGFloat(proto.params.viewBoxWidth),
                                    height: CGFloat(proto.params.viewBoxHeight))
            self.FPS = Int(proto.params.fps)
            self.frames = Int(proto.params.frames)
        }
    }

    private static func isMP3Data(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data.prefix(3) == Data("ID3".utf8)
    }
}
