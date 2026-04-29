import UIKit

@objcMembers
class SVGAExporter: NSObject {

    // MARK: - Public

    /// Video entity to export.
    var videoItem: SVGAVideoEntity?

    // MARK: - Private

    private var drawLayer: CALayer?
    private var currentFrame: Int = 0

    // MARK: - Public APIs

    /// Export all frames to images.
    func toImages() -> [UIImage] {
        var images: [UIImage] = []
        guard
            let video = videoItem,
            video.videoSize.width > 0.0,
            video.videoSize.height > 0.0
        else { return images }

        draw()

        let frameCount = Int(video.frames)
        for i in 0..<frameCount {
            currentFrame = i
            update()

            if let drawLayer = drawLayer {
                UIGraphicsBeginImageContextWithOptions(drawLayer.frame.size, false, 1.0)
                if let ctx = UIGraphicsGetCurrentContext() {
                    drawLayer.render(in: ctx)
                    if let image = UIGraphicsGetImageFromCurrentImageContext() {
                        images.append(image)
                    }
                }
                UIGraphicsEndImageContext()
            }
        }
        return images
    }

    /// Save all frames as PNG files to disk.
    /// - Parameters:
    ///   - toPath: Directory path.
    ///   - filePrefix: File name prefix. Defaults to empty string when nil.
    func saveImages(_ toPath: String, filePrefix: String?) {
        let prefix = filePrefix ?? ""
        do {
            try FileManager.default.createDirectory(atPath: toPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Ignore directory creation errors to match original behavior.
        }

        guard
            let video = videoItem,
            video.videoSize.width > 0.0,
            video.videoSize.height > 0.0
        else { return }

        draw()

        let frameCount = Int(video.frames)
        for i in 0..<frameCount {
            currentFrame = i
            update()

            if let drawLayer = drawLayer {
                UIGraphicsBeginImageContextWithOptions(drawLayer.frame.size, false, 1.0)
                if let ctx = UIGraphicsGetCurrentContext() {
                    drawLayer.render(in: ctx)
                    if let image = UIGraphicsGetImageFromCurrentImageContext(),
                       let data = image.pngData() {
                        let filePath = "\(toPath)/\(prefix)\(i).png"
                        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
                    }
                }
                UIGraphicsEndImageContext()
            }
        }
    }

    // MARK: - Drawing Pipeline

    private func draw() {
        guard let video = videoItem else { return }

        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: video.videoSize.width, height: video.videoSize.height)
        layer.masksToBounds = true

        // Build content layers for each sprite.
        for sprite in video.sprites {
            // Fetch bitmap by sprite.imageKey from video.images dictionary.
            var bitmap: UIImage?
            if let images = video.images as [String: UIImage]?,
               let imageKey = sprite.imageKey {
                bitmap = images[imageKey]
            }
            
//            if let images = video.images as? NSDictionary {
//                bitmap = images[sprite.imageKey as Any] as? UIImage
//            } else if let images = video.images as? [String: UIImage] {
//                bitmap = images[sprite.imageKey]
//            }

            // Request content layer from sprite.
            if let contentLayer = sprite.requestLayer(withBitmap: bitmap) {
                layer.addSublayer(contentLayer)
            }
        }

        drawLayer = layer
        currentFrame = 0
        update()
    }

    private func update() {
        guard let drawLayer = drawLayer else { return }
        for sublayer in drawLayer.sublayers ?? [] {
            if let content = sublayer as? SVGAContentLayer {
                content.stepToFrame(currentFrame)
            }
        }
    }
}
