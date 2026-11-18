// 2026-11-18 4:35 PM CST — "Pro meter": works out the moon exposure a pro would use, translated to this iPhone lens
import AVFoundation
import Foundation

/// Pros shoot the moon at roughly f/8–f/11, 1/100–1/250 s, ISO 100–200 (the "Looney 11" rule: f/11 at 1/ISO).
/// That is about EV 13.8 at ISO 100 for a high full moon. We adjust for tonight's phase and height,
/// then convert it to this iPhone's fixed aperture at its lowest ISO.
enum MoonMeter {
    /// Exposure value (ISO 100) for the lit part of the moon tonight.
    static func moonEV(altitude: Double, phaseAngle: Double) -> Double {
        let base = 13.8                                   // high full moon, from pro "Looney 11" settings
        // a crescent's lit surface is dimmer than a full moon's: about 1 stop at half, ~2 at a thin crescent
        let pa = min(170, max(0, phaseAngle * 180 / .pi))
        let phaseStops = pow(pa / 90, 1.3)
        // a low moon shines through much more air (orange and dimmer): air mass formula, haze about 0.25 mag per air mass
        let h = max(0.5, altitude)
        let airmass = 1 / (sin(h * .pi / 180) + 0.50572 * pow(h + 6.07995, -1.6364))
        let airStops = min(4.5, 0.25 * (airmass - 1) * 1.33)
        return base - phaseStops - airStops
    }

    /// Shutter and ISO for this lens, keeping the shutter fast enough to hold by hand.
    static func settings(for d: AVCaptureDevice, ev: Double, offsetStops: Double) -> (CMTime, Float) {
        let f = d.activeFormat
        let n = Double(max(1.4, d.lensAperture))       // iPhone lenses are fixed, about f/1.8–f/2.8
        var iso = Double(max(f.minISO, 32))
        let e = ev + offsetStops                         // positive = darker
        var t = n * n / (pow(2, e) * iso / 100)
        let slowest = 1.0 / 120                          // hand-held limit for the zoom lens
        if t > slowest { iso = min(Double(f.maxISO), iso * t / slowest); t = slowest }
        let minT = CMTimeGetSeconds(f.minExposureDuration), maxT = CMTimeGetSeconds(f.maxExposureDuration)
        t = min(max(t, minT), maxT)
        return (CMTime(seconds: t, preferredTimescale: 1_000_000), Float(min(max(iso, Double(f.minISO)), Double(f.maxISO))))
    }

    static func label(_ t: CMTime, _ iso: Float) -> String {
        let s = CMTimeGetSeconds(t)
        return "1/\(Int((1 / s).rounded())) s · ISO \(Int(iso.rounded()))"
    }
}
