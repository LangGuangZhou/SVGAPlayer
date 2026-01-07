import UIKit

@objcMembers
class SVGABezierPath: UIBezierPath {

    private var displaying: Bool = false
    private var backValues: String?

    private static let validMethods: Set<String> = [
        "M","L","H","V","C","S","Q","R","A","Z",
        "m","l","h","v","c","s","q","r","a","z"
    ]
    
    // Exposed to ObjC as: - (void)setValues:(NSString *)values;
    func setValues(_ values: String) {
        if !displaying {
            backValues = values
            return
        }

        var v = values
        v = v.replacingOccurrences(of: "([a-zA-Z])", with: "|||$1 ", options: .regularExpression, range: nil)
        v = v.replacingOccurrences(of: ",", with: " ")

        let segments = v.components(separatedBy: "|||")
        for segment in segments {
            guard !segment.isEmpty else { continue }
            let firstLetter = String(segment.prefix(1))
            guard SVGABezierPath.validMethods.contains(firstLetter) else { continue }

            let rest = String(segment.dropFirst())
            let args = rest
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }

            operate(firstLetter, args: args)
        }
    }

    // Exposed to ObjC as: - (CAShapeLayer *)createLayer;
    func createLayer() -> CAShapeLayer {
        if !displaying {
            displaying = true
            if let back = backValues {
                setValues(back)
            }
        }
        let layer = CAShapeLayer()
        layer.path = self.cgPath
        layer.fillColor = UIColor.black.cgColor
        return layer
    }

    private func operate(_ method: String, args: [String]) {
        if (method == "M" || method == "m"), args.count == 2 {
            let p = argPoint(CGPoint(x: cgFloat(args[0]), y: cgFloat(args[1])), relative: method == "m")
            move(to: p)
        }
        else if (method == "L" || method == "l"), args.count == 2 {
            let p = argPoint(CGPoint(x: cgFloat(args[0]), y: cgFloat(args[1])), relative: method == "l")
            addLine(to: p)
        }
        else if (method == "C" || method == "c"), args.count == 6 {
            let p1 = argPoint(CGPoint(x: cgFloat(args[0]), y: cgFloat(args[1])), relative: method == "c")
            let p2 = argPoint(CGPoint(x: cgFloat(args[2]), y: cgFloat(args[3])), relative: method == "c")
            let p3 = argPoint(CGPoint(x: cgFloat(args[4]), y: cgFloat(args[5])), relative: method == "c")
            addCurve(to: p3, controlPoint1: p1, controlPoint2: p2)
        }
        else if (method == "Q" || method == "q"), args.count == 4 {
            let p1 = argPoint(CGPoint(x: cgFloat(args[0]), y: cgFloat(args[1])), relative: method == "q")
            let p2 = argPoint(CGPoint(x: cgFloat(args[2]), y: cgFloat(args[3])), relative: method == "q")
            addQuadCurve(to: p2, controlPoint: p1)
        }
        else if (method == "H" || method == "h"), args.count == 1 {
            let x = argFloat(cgFloat(args[0]), relativeValue: (method == "h") ? currentPoint.x : 0.0)
            addLine(to: CGPoint(x: x, y: currentPoint.y))
        }
        else if (method == "V" || method == "v"), args.count == 1 {
            let y = argFloat(cgFloat(args[0]), relativeValue: (method == "v") ? currentPoint.y : 0.0)
            addLine(to: CGPoint(x: currentPoint.x, y: y))
        }
        else if method == "Z" || method == "z" {
            close()
        }
        // S/R/A and others in validMethods are intentionally ignored (same as original)
    }

    private func argFloat(_ value: CGFloat, relativeValue: CGFloat) -> CGFloat {
        return value + relativeValue
    }

    private func argPoint(_ point: CGPoint, relative: Bool) -> CGPoint {
        if relative {
            return CGPoint(x: point.x + currentPoint.x, y: point.y + currentPoint.y)
        } else {
            return point
        }
    }

    private func cgFloat(_ s: String) -> CGFloat {
        return CGFloat(Double(s) ?? 0.0)
    }
}
