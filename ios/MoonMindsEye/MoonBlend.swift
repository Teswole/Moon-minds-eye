// 2026-11-14 3:50 PM CST — Blend the short "moon" exposure into the normal "scene" photo, so both look right at once
import CoreImage
import CoreGraphics
import Foundation

enum MoonBlend {
    private static let context = CIContext()

    /// Returns a JPEG of the scene with the moon taken from the darker exposure, or nil if no moon was found.
    static func blend(scene: Data, moon: Data) -> Data? {
        let opts: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let s = CIImage(data: scene, options: opts), let m = CIImage(data: moon, options: opts) else { return nil }
        // Bring the moon frame to the scene's size if the two differ slightly
        let moonImg = m.extent.size == s.extent.size ? m :
            m.transformed(by: CGAffineTransform(scaleX: s.extent.width / m.extent.width, y: s.extent.height / m.extent.height))
        guard let spot = findMoon(in: moonImg) else { return nil }

        // Soft round mask: moon frame inside, scene outside
        let mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: spot.center.x, y: spot.center.y),
            "inputRadius0": spot.radius * 1.1,
            "inputRadius1": spot.radius * 1.5,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0)
        ])?.outputImage?.cropped(to: s.extent)
        guard let mask = mask else { return nil }
        // Keep whichever is brighter inside the mask, so the scene's sky glow survives around the detailed moon
        let lighter = moonImg.applyingFilter("CILightenBlendMode", parameters: [kCIInputBackgroundImageKey: s.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.2])])
        let out = lighter.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: s, kCIInputMaskImageKey: mask])
        let cs = s.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.jpegRepresentation(of: out.cropped(to: s.extent), colorSpace: cs, options: [:])
    }

    /// Any photo (HEIC or JPEG) as an upright JPEG, for the processor
    static func uprightJPEG(_ data: Data) -> Data? {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let cs = img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.jpegRepresentation(of: img, colorSpace: cs, options: [:])
    }

    /// Brightest small blob in the image: center and radius in Core Image coordinates (origin bottom-left).
    static func findMoon(in img: CIImage) -> (center: CGPoint, radius: CGFloat)? {
        let ext = img.extent
        let scale = 320 / max(ext.width, ext.height)
        let small = img.transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let w = Int(small.extent.width.rounded(.down)), h = Int(small.extent.height.rounded(.down))
        guard w > 4, h > 4, let cg = context.createCGImage(small, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h)
        let drawn = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        guard let maxV = buf.max(), maxV > 40 else { return nil }
        let t = UInt8(Double(maxV) * 0.5)
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in 0..<h { for x in 0..<w where buf[y * w + x] >= t { sx += Double(x); sy += Double(y); n += 1 } }
        guard n > 0, n < Double(w * h) * 0.05 else { return nil }
        // buffer row 0 is the top of the picture; Core Image counts from the bottom
        let cxSmall = sx / n, cyTop = sy / n
        let r = (n / Double.pi).squareRoot()
        let center = CGPoint(x: ext.minX + CGFloat(cxSmall) / scale, y: ext.minY + (CGFloat(h) - CGFloat(cyTop)) / scale)
        return (center, CGFloat(max(r, 2)) / scale)
    }
}
