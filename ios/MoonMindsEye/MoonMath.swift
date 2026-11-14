// 2026-11-14 3:10 PM CST — Moon and sun position math (same formulas as the website, accurate to about 1°)
import Foundation

struct MoonState {
    let altitude: Double      // degrees above the horizon
    let bearing: Double       // compass degrees (0 = north)
    let fraction: Double      // 0...1 lit
    let waxing: Bool
    let brightLimbAngle: Double   // radians, from north toward east
    let phaseAngle: Double        // radians
    let parallactic: Double       // radians
}

enum MoonMath {
    static let rad = Double.pi / 180
    private static let obliquity = rad * 23.4397

    static func toDays(_ d: Date) -> Double { d.timeIntervalSince1970 / 86400 - 0.5 + 2440588 - 2451545 }
    private static func rightAscension(_ l: Double, _ b: Double) -> Double { atan2(sin(l) * cos(obliquity) - tan(b) * sin(obliquity), cos(l)) }
    private static func declination(_ l: Double, _ b: Double) -> Double { asin(sin(b) * cos(obliquity) + cos(b) * sin(obliquity) * sin(l)) }
    private static func azimuth(_ h: Double, _ phi: Double, _ dec: Double) -> Double { atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi)) }
    private static func altitude(_ h: Double, _ phi: Double, _ dec: Double) -> Double { asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h)) }
    private static func siderealTime(_ d: Double, _ lw: Double) -> Double { rad * (280.16 + 360.9856235 * d) - lw }
    private static func refraction(_ h0: Double) -> Double { let h = max(0, h0); return 0.0002967 / tan(h + 0.00312536 / (h + 0.08901179)) }

    private static func sunCoords(_ d: Double) -> (dec: Double, ra: Double) {
        let m = rad * (357.5291 + 0.98560028 * d)
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let l = m + c + rad * 102.9372 + Double.pi
        return (declination(l, 0), rightAscension(l, 0))
    }
    private static func moonCoords(_ d: Double) -> (ra: Double, dec: Double, dist: Double) {
        let l0 = rad * (218.316 + 13.176396 * d), m = rad * (134.963 + 13.064993 * d), f = rad * (93.272 + 13.229350 * d)
        let l = l0 + rad * 6.289 * sin(m), b = rad * 5.128 * sin(f)
        return (rightAscension(l, b), declination(l, b), 385001 - 20905 * cos(m))
    }

    static func sunAltitude(_ date: Date, lat: Double, lng: Double) -> Double {
        let lw = rad * -lng, phi = rad * lat, d = toDays(date), s = sunCoords(d), h = siderealTime(d, lw) - s.ra
        return altitude(h, phi, s.dec) / rad
    }

    static func moon(_ date: Date, lat: Double, lng: Double) -> MoonState {
        let lw = rad * -lng, phi = rad * lat, d = toDays(date), c = moonCoords(d), h = siderealTime(d, lw) - c.ra
        var alt = altitude(h, phi, c.dec); alt += refraction(alt)
        let q = atan2(sin(h), tan(phi) * cos(c.dec) - sin(c.dec) * cos(h))
        let s = sunCoords(d), sd = 149598000.0
        let phi2 = acos(sin(s.dec) * sin(c.dec) + cos(s.dec) * cos(c.dec) * cos(s.ra - c.ra))
        let inc = atan2(sd * sin(phi2), c.dist - sd * cos(phi2))
        let angle = atan2(cos(s.dec) * sin(s.ra - c.ra), sin(s.dec) * cos(c.dec) - cos(s.dec) * sin(c.dec) * cos(s.ra - c.ra))
        let bearing = (azimuth(h, phi, c.dec) / rad + 540).truncatingRemainder(dividingBy: 360)
        return MoonState(altitude: alt / rad, bearing: bearing, fraction: (1 + cos(inc)) / 2, waxing: angle < 0,
                         brightLimbAngle: angle, phaseAngle: inc, parallactic: q)
    }

    static func phaseName(_ m: MoonState) -> String {
        let f = m.fraction
        if f < 0.03 { return "New Moon" }
        if f > 0.97 { return "Full Moon" }
        if abs(f - 0.5) < 0.04 { return m.waxing ? "First Quarter" : "Last Quarter" }
        return (m.waxing ? "Waxing " : "Waning ") + (f < 0.5 ? "Crescent" : "Gibbous")
    }

    static func compass(_ b: Double) -> String {
        let names = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return names[Int((b / 22.5).rounded()) % 16]
    }

    /// Next "illusion zone": moon 0–10° up while the sky is getting dark or dark.
    static func nextWindow(from now: Date, lat: Double, lng: Double, days: Double = 2) -> (start: Date, end: Date?)? {
        var start: Date? = nil
        var t = now
        let end = now.addingTimeInterval(days * 86400)
        while t <= end {
            let m = moon(t, lat: lat, lng: lng), s = sunAltitude(t, lat: lat, lng: lng)
            let ok = m.altitude >= 0 && m.altitude <= 10 && s < 2
            if ok && start == nil { start = t }
            if !ok, let st = start { return (st, t) }
            t = t.addingTimeInterval(300)
        }
        if let st = start { return (st, nil) }
        return nil
    }
}
