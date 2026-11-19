// 2026-11-18 8:40 PM CST — Shot Coach: kid-friendly steps at the bottom of the live camera that check themselves off and take the photo
import Foundation
import CoreMotion
import SwiftUI

final class ShotCoach: ObservableObject {
    enum Step: Int, CaseIterable { case find, zoom, frame, still, shoot, done
        var title: String {
            switch self {
            case .find:  return "Find the moon"
            case .zoom:  return "Zoom in"
            case .frame: return "Show the ground"
            case .still: return "Hold still"
            case .shoot: return "Taking your photo"
            case .done:  return "You did it!"
            }
        }
    }
    @Published var step: Step = .find
    @Published var hint = "Point your phone at the moon. Look for the gold ring."
    @Published var progress: Double = 0           // 0...1 for the hold-still ring
    @Published var countdown: Int? = nil
    @Published var fact = ""
    @Published var autoShoot = true

    private let motion = CMMotionManager()
    private var timer: Timer?
    private var stillSince: Date?
    private var lostSince: Date?
    private var switchedLens = false
    private var sawBusy = false
    private weak var camera: CameraModel?
    private var lat: Double?, lng: Double?

    static let facts = [
        "The moon is about 239,000 miles away. A car driving nonstop would take about 5 months to get there!",
        "The moon doesn't make its own light. It shines with sunlight bouncing off it.",
        "The moon always shows Earth the same face. Its far side was first photographed in 1959.",
        "12 astronauts have walked on the moon. Their footprints are still there, because there's no wind.",
        "The big dark patches on the moon are old lava plains called 'maria', which means 'seas'.",
        "A low moon looks huge, but it's the same size as a high moon. Your brain makes it look bigger!",
        "The moon moves about 1.5 inches farther from Earth every year.",
        "On the moon you would weigh about 1/6 of what you weigh on Earth. You could jump 6 times higher!",
        "A low moon looks orange because its light passes through more air, which scatters the blue away.",
        "The moon's craters were made by space rocks crashing into it billions of years ago."
    ]

    func begin(camera: CameraModel, lat: Double?, lng: Double?) {
        self.camera = camera; self.lat = lat; self.lng = lng
        step = .find; switchedLens = false; sawBusy = false; stillSince = nil; lostSince = nil; countdown = nil; progress = 0
        fact = Self.facts.randomElement() ?? ""
        if motion.isDeviceMotionAvailable { motion.deviceMotionUpdateInterval = 0.1; motion.startDeviceMotionUpdates() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        update()
    }

    func end() { timer?.invalidate(); timer = nil; motion.stopDeviceMotionUpdates(); countdown = nil }

    func again() { guard let c = camera else { return }; begin(camera: c, lat: lat, lng: lng) }

    /// How shaky the phone is right now (radians per second)
    private var shake: Double {
        guard let r = motion.deviceMotion?.rotationRate else { return 0 }
        return sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
    }

    private func tick() {
        guard let c = camera else { return }
        if c.busy { sawBusy = true; if step != .done { step = .shoot; hint = "Keep still… taking a scene shot and 3 moon shots." }; return }
        if step == .shoot { if sawBusy { sawBusy = false; finish() }; return }   // wait for the shot to actually start and finish
        if step == .done { return }

        let locked = c.moonPoint != nil
        // losing the moon for more than 2 seconds sends you back to step 1
        if !locked { if lostSince == nil { lostSince = Date() } } else { lostSince = nil }
        if let l = lostSince, Date().timeIntervalSince(l) > 2, step.rawValue > Step.find.rawValue { step = .find; countdown = nil }

        switch step {
        case .find:
            if locked { advance(to: .zoom) }
        case .zoom:
            // switch to the zoom lens for you, once
            if let tele = c.lenses.first(where: { $0.label == "Zoom lens" }) {
                if c.currentLensID == tele.id { advance(to: .frame) }
                else if !switchedLens { switchedLens = true; c.selectLens(tele.id) }
            } else { advance(to: .frame) }   // this phone has one lens: nothing to do
        case .frame:
            // moon in the top part of the picture, so trees or rooftops fit below it
            if let p = c.moonPoint, p.x < 0.5 { advance(to: .still) }
        case .still:
            guard locked else { break }
            if shake < 0.08 {
                if stillSince == nil { stillSince = Date() }
                let held = Date().timeIntervalSince(stillSince!)
                progress = min(1, held / 2)
                if held >= 2 {
                    if autoShoot { countdownAndShoot() } else { hint = "Great and steady! Tap the round button." }
                }
            } else { stillSince = nil; progress = 0 }
        default: break
        }
    }

    private func advance(to s: Step) {
        step = s; stillSince = nil; progress = 0; update()
    }

    private func update() {
        let low = moonAltitude().map { $0 <= 10 } ?? true
        switch step {
        case .find:  hint = "Point your phone at the moon. When the gold ring circles it, you've got it!"
        case .zoom:  hint = "Switching to the zoom lens to make the moon bigger…"
        case .frame: hint = "Tilt down a little so trees, houses or rooftops show under the moon. Pros always include the ground!"
        case .still: hint = "Hold very still, like a statue. Lean on a car, post or fence if you can." + (low ? "" : " (The moon is high tonight. It looks biggest when it's low.)")
        case .shoot: hint = "Keep still… taking a scene shot and 3 moon shots."
        case .done:  hint = "Your mind's-eye photo is saved to Photos."
        }
    }

    private func countdownAndShoot() {
        guard countdown == nil, let c = camera else { return }
        countdown = 3; hint = "Get ready…"
        func next() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self = self, let n = self.countdown else { return }
                if self.camera?.moonPoint == nil || self.shake > 0.15 { self.countdown = nil; self.stillSince = nil; self.progress = 0; self.update(); return }   // moved: try again
                if n > 1 { self.countdown = n - 1; next() }
                else { self.countdown = nil; self.step = .shoot; self.update(); c.captureMindsEye(lat: self.lat, lng: self.lng) }
            }
        }
        next()
    }

    private func finish() {
        step = .done; update(); fact = Self.facts.randomElement() ?? fact
    }

    private func moonAltitude() -> Double? {
        guard let lat = lat, let lng = lng else { return nil }
        return MoonMath.moon(Date(), lat: lat, lng: lng).altitude
    }
}

/// The coach card at the bottom of the live camera
struct CoachCard: View {
    @ObservedObject var coach: ShotCoach
    let gold = Color(red: 0.96, green: 0.78, blue: 0.42)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach([ShotCoach.Step.find, .zoom, .frame, .still, .shoot], id: \.rawValue) { s in
                    let done = coach.step.rawValue > s.rawValue
                    ZStack {
                        Circle().fill(done ? Color.green : (coach.step == s ? gold : Color.white.opacity(0.18))).frame(width: 26, height: 26)
                        if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) }
                        else { Text("\(s.rawValue + 1)").font(.caption.bold()).foregroundStyle(coach.step == s ? .black : .white) }
                    }
                    if s != .shoot { Rectangle().fill(done ? Color.green : Color.white.opacity(0.18)).frame(height: 2) }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(coach.step.title).font(.headline)
                Spacer()
                if let n = coach.countdown { Text("\(n)").font(.title.bold()).foregroundStyle(gold) }
                else if coach.step == .still { ProgressView(value: coach.progress).tint(gold).frame(width: 70) }
            }
            Text(coach.hint).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if coach.step == .done {
                Text("🌙 Space fact: \(coach.fact)").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Take another") { coach.again() }.font(.subheadline.bold()).foregroundStyle(gold)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 14)
    }
}
