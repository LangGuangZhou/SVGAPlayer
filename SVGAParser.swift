import Foundation
import UIKit
import SSZipArchive
import zlib
import CommonCrypto

@objcMembers
final class SVGAParser: NSObject {

    // MARK: - Types

    typealias SVGACompletionBlock = (SVGAVideoEntity?) -> Void
    typealias SVGAFailureBlock = (NSError?) -> Void

    // MARK: - Public Properties

    var enabledMemoryCache: Bool = false
    var disableLoadFromMemory: Bool = false
    weak var vc: UIViewController?

    // MARK: - Static (shared queues and callback maps)

    private static let parseQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 8
        return q
    }()

    private static let unzipQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private static var completionMap: [String: [SVGACompletionBlock]] = [:]
    private static var failureMap: [String: [SVGAFailureBlock]] = [:]

    // MARK: - Public APIs
    @objc(parseWithURL:completionBlock:failureBlock:)
    func parse(with url: URL,
               completionBlock: @escaping SVGACompletionBlock,
               failureBlock: SVGAFailureBlock? = nil) {
        let request = URLRequest(url: url,
                                 cachePolicy: .returnCacheDataElseLoad,
                                 timeoutInterval: 20.0)
        parse(withURLRequest: request,
              completionBlock: completionBlock,
              failureBlock: failureBlock)
    }
    
    @objc(parseWithNamed:inBundle:completionBlock:failureBlock:)
    func parse(withNamed named: String,
               in bundle: Bundle?,
               completionBlock: @escaping SVGACompletionBlock,
               failureBlock: SVGAFailureBlock? = nil) {
        let bundle = bundle ?? .main
        guard let filePath = bundle.path(forResource: named, ofType: "svga"),
              !filePath.isEmpty
        else {
            if let failureBlock {
                OperationQueue.main.addOperation {
                    failureBlock(NSError(domain: "SVGAParser", code: 404,
                                         userInfo: [NSLocalizedDescriptionKey: "File not exist."]))
                }
            }
            return
        }

        // Memory cache
        let cacheKey = cacheKey(URL(fileURLWithPath: filePath))
        if let cacheItem = SVGAVideoEntity.readCache(cacheKey, vc: vc), !disableLoadFromMemory {
            OperationQueue.main.addOperation {
                NSLog("svga load from cache %@", filePath)
                completionBlock(cacheItem)
            }
            return
        }

        Self.parseQueue.addOperation { [weak self] in
            guard let self = self else { return }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)), data.count >= 4 else {
                return
            }
            if !Self.isZIPData(data) {
                // Maybe SVGA 2.0.0
                self.innerParseWithProtoData(data, cacheKey: cacheKey,
                                             completionBlock: completionBlock,
                                             failureBlock: failureBlock)
                return
            }
            self.innerParseWithZipData(data, cacheKey: cacheKey,
                                       completionBlock: completionBlock,
                                       failureBlock: failureBlock)
        }
    }

    func videoCacheKey(_ urlStr: String) -> String {
        return md5String(urlStr)
    }

    // MARK: - Private Main Entry

    private func parse(withURLRequest urlRequest: URLRequest,
                       completionBlock: @escaping SVGACompletionBlock,
                       failureBlock: SVGAFailureBlock? = nil) {
        let key = cacheKey(urlRequest.url)

        // Memory cache
        if let cacheItem = SVGAVideoEntity.readCache(key, vc: vc), !disableLoadFromMemory {
            OperationQueue.main.addOperation {
                NSLog("svga load from cache %@", urlRequest.url?.absoluteString ?? "")
                completionBlock(cacheItem)
            }
            return
        }

        // File cache (proto or json)
        let protoPath = cacheProtoFilepath(key)
        let jsonPath = cacheJsonFilepath(key)
        if FileManager.default.fileExists(atPath: protoPath) ||
           FileManager.default.fileExists(atPath: jsonPath) {
            parseFromFileCacheKey(key, completionBlock: { videoItem in
                NSLog("svga load from file success %@", self.cacheDirectory(key))
                OperationQueue.main.addOperation {
                    completionBlock(videoItem)
                }
            }, failureBlock: { error in
                NSLog("svga load from file failure %@ path: %@", error?.localizedDescription ?? "", self.cacheDirectory(key))
                self.clearCache(key)
                if let failureBlock {
                    OperationQueue.main.addOperation {
                        failureBlock(error)
                    }
                }
            })
            return
        }

        // Save failure callback
        if let failureBlock {
            if let exists = Self.failureMap[key] {
                var arr = exists
                arr.append(failureBlock)
                Self.failureMap[key] = arr
            } else {
                Self.failureMap[key] = [failureBlock]
            }
        }

        // Save completion callback and coalesce requests
        if var exists = Self.completionMap[key] {
            exists.append(completionBlock)
            Self.completionMap[key] = exists
            return
        }
        Self.completionMap[key] = [completionBlock]

        // Download
        NSLog("svga load from net download begin %@", urlRequest.url?.absoluteString ?? "")
        let startTime = CACurrentMediaTime()
        URLSession.shared.downloadTask(with: urlRequest) { [weak self] location, _, error in
            guard let self = self else { return }
            if let error = error as NSError? {
                NSLog("svga load from net ❌ %@ error：%@", urlRequest.url?.absoluteString ?? "", error.localizedDescription)
                self.executeCacheFailure(key, error: error)
                return
            }
            self.parseWithDownloadLocation(location, cacheKey: key, completionBlock: { video in
                NSLog("svga load from net %@ consume time：%@", urlRequest.url?.absoluteString ?? "", NSNumber(value: CACurrentMediaTime() - startTime))
                self.executeCacheCompletion(key, videoItem: video)
            }, failureBlock: { err in
                NSLog("svga load from net ❌ %@", err?.localizedDescription ?? "")
                self.clearCache(key)
                self.executeCacheFailure(key, error: err)
            })
        }.resume()
    }

    // MARK: - File/Cache Paths

    private func cacheKey(_ url: URL?) -> String {
        return md5String(url?.absoluteString ?? "")
    }

    private func cacheDirectory(_ cacheKey: String) -> String {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return (cacheDir as NSString).appendingPathComponent("svga/\(cacheKey)")
    }

    private func cacheProtoFilepath(_ cacheKey: String) -> String {
        return (cacheDirectory(cacheKey) as NSString).appendingPathComponent("movie.binary")
    }

    private func cacheJsonFilepath(_ cacheKey: String) -> String {
        return (cacheDirectory(cacheKey) as NSString).appendingPathComponent("movie.spec")
    }

    private func clearCache(_ cacheKey: String) {
        let dir = cacheDirectory(cacheKey)
        try? FileManager.default.removeItem(atPath: dir)
        NSLog("svga load clear file %@", cacheKey)
    }

    // MARK: - Parse From Disk

    private func parseFromFileCacheKey(_ cacheKey: String,
                                       completionBlock: SVGACompletionBlock?,
                                       failureBlock: SVGAFailureBlock?) {
        Self.parseQueue.addOperation { [weak self] in
            guard let self = self else { return }
            let protoPath = self.cacheProtoFilepath(cacheKey)
            if FileManager.default.fileExists(atPath: protoPath) {
                let data = try? Data(contentsOf: URL(fileURLWithPath: protoPath))
                self.innerParseWithProtoData(data, cacheKey: cacheKey,
                                             completionBlock: completionBlock,
                                             failureBlock: failureBlock)
                return
            }
            let jsonPath = self.cacheJsonFilepath(cacheKey)
            if FileManager.default.fileExists(atPath: jsonPath) {
                let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath))
                self.innerParseWithJsonData(data, cacheKey: cacheKey,
                                            completionBlock: completionBlock,
                                            failureBlock: failureBlock)
                return
            }
        }
    }

    // MARK: - Parse From Download Temp Location

    private func parseWithDownloadLocation(_ location: URL?,
                                           cacheKey: String,
                                           completionBlock: SVGACompletionBlock?,
                                           failureBlock: SVGAFailureBlock?) {
        let cacheDir = cacheDirectory(cacheKey)
        let filepath = (cacheDir as NSString).appendingPathComponent("movie.binary")

        var fileError: NSError?
        if !FileManager.default.fileExists(atPath: cacheDir) {
            do {
                try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true, attributes: nil)
            } catch let err as NSError {
                fileError = err
            }
        }

        if let loc = location {
            do {
                // Move before URLSession completion returns
                try FileManager.default.moveItem(at: loc, to: URL(fileURLWithPath: filepath))
            } catch let err as NSError {
                fileError = err
            }
        } else {
            fileError = NSError(domain: NSFilePathErrorKey, code: -1, userInfo: nil)
        }

        if let fileError {
            failureBlock?(fileError)
            return
        }

        Self.parseQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filepath), options: .mappedIfSafe)
                if Self.isZIPData(data) {
                    self.innerParseWithZipData(data, cacheKey: cacheKey,
                                               completionBlock: completionBlock,
                                               failureBlock: failureBlock)
                    return
                }
                self.innerParseWithProtoData(data, cacheKey: cacheKey,
                                             completionBlock: completionBlock,
                                             failureBlock: failureBlock)
            } catch let err as NSError {
                if let failureBlock {
                    OperationQueue.main.addOperation {
                        failureBlock(err)
                    }
                }
            }
        }
    }

    // MARK: - Inner Parse - Proto

    private func innerParseWithProtoData(_ data: Data?,
                                         cacheKey: String,
                                         completionBlock: SVGACompletionBlock?,
                                         failureBlock: SVGAFailureBlock?) {
        guard let data = data else {
            if let failureBlock {
                OperationQueue.main.addOperation {
                    failureBlock(NSError(domain: NSFilePathErrorKey, code: -1, userInfo: nil))
                }
            }
            return
        }

        guard let inflateData = zlibInflate(data) else {
            if let failureBlock {
                OperationQueue.main.addOperation {
                    failureBlock(NSError(domain: "ZlibInflateError", code: -1, userInfo: nil))
                }
            }
            return
        }

        do {
            let protoObject = try SVGAProtoMovieEntity.parse(from: inflateData)
            let videoItem = SVGAVideoEntity(protoObject: protoObject, cacheDir: "")
            videoItem.resetImages(withProtoObject: protoObject)
            videoItem.resetSprites(withProtoObject: protoObject)
            videoItem.resetAudios(withProtoObject: protoObject)
            if enabledMemoryCache {
                videoItem.saveCache(cacheKey, vc: vc)
            }
            if let completionBlock {
                OperationQueue.main.addOperation {
                    completionBlock(videoItem)
                }
            }
        } catch let err as NSError {
            if let failureBlock {
                OperationQueue.main.addOperation {
                    failureBlock(err)
                }
            }
        }
    }

    // MARK: - Inner Parse - JSON

    private func innerParseWithJsonData(_ data: Data?,
                                        cacheKey: String,
                                        completionBlock: SVGACompletionBlock?,
                                        failureBlock: SVGAFailureBlock?) {
        guard let data = data else {
            if let failureBlock {
                OperationQueue.main.addOperation {
                    failureBlock(NSError(domain: NSFilePathErrorKey, code: -1, userInfo: nil))
                }
            }
            return
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let json = obj as? [String: Any] else { return }
            let videoItem = SVGAVideoEntity(JSONObject: json as NSDictionary, cacheDir: cacheDirectory(cacheKey))
            videoItem.resetImages(withJSONObject: json as NSDictionary)
            videoItem.resetSprites(withJSONObject: json as NSDictionary)
            if enabledMemoryCache {
                videoItem.saveCache(cacheKey)
            }
            if let completionBlock {
                OperationQueue.main.addOperation {
                    completionBlock(videoItem)
                }
            }
        } catch let err as NSError {
            if let failureBlock {
                OperationQueue.main.addOperation {
                    failureBlock(err)
                }
            }
        }
    }

    // MARK: - Inner Parse - Zip

    private func innerParseWithZipData(_ data: Data?,
                                       cacheKey: String,
                                       completionBlock: SVGACompletionBlock?,
                                       failureBlock: SVGAFailureBlock?) {
        Self.unzipQueue.addOperation { [weak self] in
            guard let self = self else { return }
            let tmpPath = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("\(arc4random()).svga")

            guard let data = data else {
                if let failureBlock {
                    OperationQueue.main.addOperation {
                        failureBlock(NSError(domain: "Data Error", code: -1, userInfo: nil))
                    }
                }
                return
            }

            try? data.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
            let cacheDir = self.cacheDirectory(cacheKey)
            try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: false, attributes: nil)

            SSZipArchive.unzipFile(atPath: tmpPath, toDestination: cacheDir, progressHandler: { _, _, _, _ in
                // ignore progress
            }, completionHandler: { path, succeeded, error in
                if let error = error as NSError? {
                    if let failureBlock {
                        OperationQueue.main.addOperation {
                            failureBlock(error)
                        }
                    }
                    return
                }

                let protoPath = (cacheDir as NSString).appendingPathComponent("movie.binary")
                if FileManager.default.fileExists(atPath: protoPath) {
                    do {
                        let protoData = try Data(contentsOf: URL(fileURLWithPath: protoPath))
                        let protoObject = try SVGAProtoMovieEntity.parse(from: protoData)
                        let videoItem = SVGAVideoEntity(protoObject: protoObject, cacheDir: cacheDir)
                        videoItem.resetImages(withProtoObject: protoObject)
                        videoItem.resetSprites(withProtoObject: protoObject)
                        if self.enabledMemoryCache {
                            videoItem.saveCache(cacheKey)
                        }
                        if let completionBlock {
                            OperationQueue.main.addOperation {
                                completionBlock(videoItem)
                            }
                        }
                    } catch let err as NSError {
                        if let failureBlock {
                            OperationQueue.main.addOperation {
                                failureBlock(err)
                            }
                        }
                    }
                } else {
                    let jsonPath = (cacheDir as NSString).appendingPathComponent("movie.spec")
                    let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonPath))
                    self.innerParseWithJsonData(jsonData, cacheKey: cacheKey,
                                                completionBlock: completionBlock,
                                                failureBlock: failureBlock)
                }
            })
        }
    }

    // MARK: - Callback Coalescing

    private func executeCacheCompletion(_ cacheKey: String, videoItem: SVGAVideoEntity?) {
        if let list = Self.completionMap[cacheKey] {
            for block in list {
                OperationQueue.main.addOperation {
                    block(videoItem)
                }
            }
            Self.completionMap.removeValue(forKey: cacheKey)
            Self.failureMap.removeValue(forKey: cacheKey)
        }
    }

    private func executeCacheFailure(_ cacheKey: String, error: NSError?) {
        if let list = Self.failureMap[cacheKey] {
            for block in list {
                OperationQueue.main.addOperation {
                    block(error)
                }
            }
            Self.failureMap.removeValue(forKey: cacheKey)
            Self.completionMap.removeValue(forKey: cacheKey)
        }
    }

    // MARK: - Utils

    private func md5String(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private func zlibInflate(_ data: Data) -> Data? {
        if data.isEmpty { return data }

        var stream = z_stream()
        var status: Int32

        data.withUnsafeBytes { (rawBytes: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawBytes.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uint(data.count)
        }
        stream.total_out = 0
        stream.zalloc = nil
        stream.zfree = nil

        status = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if status != Z_OK { return nil }

        var decompressed = Data(capacity: data.count * 2)
        let chunkSize = max(1024, data.count / 2)

        repeat {
            var out = [UInt8](repeating: 0, count: chunkSize)
            out.withUnsafeMutableBytes { outPtr in
                stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uint(chunkSize)
                status = inflate(&stream, Z_SYNC_FLUSH)
            }
            let outputLen = chunkSize - Int(stream.avail_out)
            if outputLen > 0 {
                decompressed.append(out, count: outputLen)
            }
        } while status == Z_OK

        guard inflateEnd(&stream) == Z_OK else { return nil }
        return (status == Z_STREAM_END && !decompressed.isEmpty) ? decompressed : nil
    }

    private static func isZIPData(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data.withUnsafeBytes { bytes -> Bool in
            let b = bytes.bindMemory(to: UInt8.self)
            return b[0] == 0x50 && b[1] == 0x4B // 'P''K'
        }
    }
}
