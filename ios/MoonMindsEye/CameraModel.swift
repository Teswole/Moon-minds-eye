// 2026-11-18 10:30 PM CST — Camera: live view, lens choice, moon finder, two-exposure shot, then the mind's-eye processor
import AVFoundation
import UIKit
import Photos

final class CameraModel: NSObject, ObservableObject {
    struct Lens: Identifiable, Hashable {
        let id: String
        let label: String
    }

    let session = AVCaptureSession()
    @Published var lenses: [Lens] = []
    @Published var currentLensID: String?
    @Published var moonPoint: CGPoint?          // in camera-sensor coordinates (0...1)
    @Published var status = "Starting camera…"
    @Published var meterNote = ""
    @Published var busy = false
    @Published var lastResult: UIImage?
    @Published var lastBefore: UIImage?
    @Published var lastChecks = ""
    @Published var showResult = false
    @Published var rebuildMoon = true
    @Published var mindsEyeSky = false
    @Published var aiSky = true
    @Published var moonExposure = true {
        didSet { sessionQueue.async { self.applyPreviewExposure() } }
    }

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var aimedAt: CGPoint?            // where focus and brightness are currently measured
    private var lastAim = Date.distantPast
    private var devices: [String: AVCaptureDevice] = [:]
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var lastDetect = Date.distantPast
    private var catchers: [PhotoCatcher] = []
    private var configured = false

    // MARK: - Setup

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else {
                DispatchQueue.main.async { self.status = "Camera access is off. Turn it on in Settings → Moon Mind's Eye → Camera." }
                return
            }
            self.sessionQueue.async {
                if !self.configured { self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back).devices
        var list: [Lens] = []
        for d in found {
            devices[d.uniqueID] = d
            list.append(Lens(id: d.uniqueID, label: d.deviceType == .builtInTelephotoCamera ? "Zoom lens" : "1x"))
        }
        let first = found.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? found.first
        if let d = first { attach(d) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()
        DispatchQueue.main.async {
            self.lenses = list
            self.currentLensID = first?.uniqueID
            self.status = first == nil ? "No back camera found." : "Point at the moon"
        }
    }

    private func attach(_ d: AVCaptureDevice) {
        if let old = input { session.removeInput(old) }
        guard let newInput = try? AVCaptureDeviceInput(device: d), session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        input = newInput
        device = d
        // Focus far away and let the camera fine-tune it (a fixed lens setting can leave the moon soft on some iPhones)
        if (try? d.lockForConfiguration()) != nil {
            if d.isAutoFocusRangeRestrictionSupported { d.autoFocusRangeRestriction = .far }
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            d.unlockForConfiguration()
        }
        aimedAt = nil
        applyPreviewExposure()
    }

    func selectLens(_ id: String) {
        sessionQueue.async {
            guard let d = self.devices[id] else { return }
            self.session.beginConfiguration()
            self.attach(d)
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.currentLensID = id }
        }
    }

    /// While aiming, darken the view a little so the moon shows detail instead of a white blob.
    private func applyPreviewExposure() {
        guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
        if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
        let bias: Float = moonExposure ? max(d.minExposureTargetBias, -1.0) : 0
        d.setExposureTargetBias(bias, completionHandler: nil)
        d.unlockForConfiguration()
    }

    // MARK: - The mind's-eye shot: one photo for the scene, one short exposure for the moon

    func captureMindsEye(lat: Double? = nil, lng: Double? = nil) {
        guard !busy else { return }
        DispatchQueue.main.async { self.busy = true; self.status = "Hold still…" }
        sessionQueue.async {
            guard let d = self.device else { self.finish(nil, message: "No camera."); return }
            // Pro meter: tonight's moon brightness from its height and phase (pros: ~f/10, 1/160 s, ISO 160 at 600mm)
            var ev = 12.5
            if let lat = lat, let lng = lng { let m = MoonMath.moon(Date(), lat: lat, lng: lng); ev = MoonMeter.moonEV(altitude: m.altitude, phaseAngle: m.phaseAngle) }
            // 1) Scene: like a pro's twilight frame, a touch darker than auto so the sky glow keeps its color
            self.setAutoExposure(d, bias: -0.3) {
                self.shoot(quality: .quality) { scene in
                    // 2) Moon: three metered frames (a pro "bracket"), then keep the one with the most real detail
                    self.bracketMoon(d, ev: ev, offsets: [0, 1, -1], got: []) { frames in
                            self.sessionQueue.async { self.applyPreviewExposure() }
                            let pick = MoonCameraPick.best(frames)
                            guard let scene = scene, let moon = pick?.data else { self.finish(nil, message: "The photo didn't come through. Try again."); return }
                            if let p = pick { DispatchQueue.main.async { self.meterNote = "Moon metered at \(p.label)" } }
                            DispatchQueue.main.async { self.status = "Blending the moon…" }
                            DispatchQueue.global(qos: .userInitiated).async {
                                let base = MoonBlend.blend(scene: scene, moon: moon) ?? MoonBlend.uprightJPEG(scene) ?? scene
                                DispatchQueue.main.async { self.runProcessor(base, lat: lat, lng: lng) }
                            }
                    }
                }
            }
        }
    }

    /// Take one moon frame per exposure offset (in stops), then hand back all of them
    private func bracketMoon(_ d: AVCaptureDevice, ev: Double, offsets: [Double], got: [MoonCameraPick.Frame], done: @escaping ([MoonCameraPick.Frame]) -> Void) {
        guard let off = offsets.first else { done(got); return }
        let (t, iso) = MoonMeter.settings(for: d, ev: ev, offsetStops: off)
        sessionQueue.async { self.setMoonExposure(d, duration: t, iso: iso) {
            self.shoot(quality: .balanced) { data in
                var list = got
                if let data = data { list.append(.init(data: data, label: MoonMeter.label(t, iso), offset: off)) }
                self.bracketMoon(d, ev: ev, offsets: Array(offsets.dropFirst()), got: list, done: done)
            }
        } }
    }

    /// Step 3: the mind's-eye processor (moon rebuild, sky AI, twilight sky, enlarging)
    private func runProcessor(_ base: Data, lat: Double?, lng: Double?) {
        status = "Rebuilding the moon…"
        let rebuild = rebuildMoon, sky = mindsEyeSky, ai = aiSky
        Task { @MainActor in
            var final = base
            var checks = "Saved the photo as taken"
            do {
                let r = try await WebProcessor.shared.process(base, lat: lat, lng: lng, when: Date(),
                                                              rebuild: rebuild, mindsEyeSky: sky, aiSky: ai)
                if let jpeg = r.jpeg { final = jpeg }
                checks = r.found ? ([r.size.isEmpty ? nil : "Moon \(r.size)", r.checks].compactMap { $0 }.joined(separator: " · "))
                                 : "Moon not found, so the photo was saved as taken"
            } catch {
                checks = "The processor had a problem, so the photo was saved as taken"
            }
            self.save(final)
            self.lastBefore = UIImage(data: base)
            self.lastResult = UIImage(data: final)
            self.lastChecks = self.meterNote.isEmpty ? checks : checks + " · " + self.meterNote
            self.status = "Saved to Photos"
            self.busy = false
            self.showResult = true
        }
    }

    private func setAutoExposure(_ d: AVCaptureDevice, bias: Float, then: @escaping () -> Void) {
        guard (try? d.lockForConfiguration()) != nil else { then(); return }
        if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
        d.setExposureTargetBias(bias) { _ in
            // give auto-exposure a moment to settle
            self.sessionQueue.asyncAfter(deadline: .now() + 0.6) { then() }
        }
        d.unlockForConfiguration()
    }

    private func setMoonExposure(_ d: AVCaptureDevice, duration: CMTime, iso: Float, then: @escaping () -> Void) {
        guard d.isExposureModeSupported(.custom), (try? d.lockForConfiguration()) != nil else { then(); return }
        d.setExposureModeCustom(duration: duration, iso: iso) { _ in
            self.sessionQueue.asyncAfter(deadline: .now() + 0.15) { then() }
        }
        d.unlockForConfiguration()
    }

    private func shoot(quality: AVCapturePhotoOutput.QualityPrioritization, done: @escaping (Data?) -> Void) {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        let maxQ = photoOutput.maxPhotoQualityPrioritization
        settings.photoQualityPrioritization = quality.rawValue <= maxQ.rawValue ? quality : maxQ
        let catcher = PhotoCatcher { [weak self] data, c in
            self?.sessionQueue.async { self?.catchers.removeAll { $0 === c } }
            done(data)
        }
        catchers.append(catcher)
        photoOutput.capturePhoto(with: settings, delegate: catcher)
    }

    private func save(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }, completionHandler: nil)
        }
    }

    private func finish(_ image: UIImage?, message: String) {
        DispatchQueue.main.async {
            if let image = image { self.lastResult = image }
            self.status = message
            self.busy = false
        }
    }
}

// MARK: - Moon finder on the live video (brightest small spot)

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastDetect) > 0.25, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetect = Date()
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let p = base.assumingMemoryBound(to: UInt8.self)
        let step = 4
        var maxV: UInt8 = 0
        for y in Swift.stride(from: 0, to: h, by: step) {
            for x in Swift.stride(from: 0, to: w, by: step) {
                let v = p[y * rowBytes + x]
                if v > maxV { maxV = v }
            }
        }
        var point: CGPoint? = nil
        if maxV > 60 {
            let t = UInt8(Double(maxV) * 0.8)
            var sx = 0.0, sy = 0.0, n = 0.0
            for y in Swift.stride(from: 0, to: h, by: step) {
                for x in Swift.stride(from: 0, to: w, by: step) where p[y * rowBytes + x] >= t {
                    sx += Double(x); sy += Double(y); n += 1
                }
            }
            let samples = Double((w / step) * (h / step))
            if n > 0 && n < samples * 0.08 {     // small and bright: moon-like, not a lit wall
                point = CGPoint(x: sx / n / Double(w), y: sy / n / Double(h))
            }
        }
        DispatchQueue.main.async { self.moonPoint = point }
        aim(at: point)
    }

    /// Measure focus and brightness on the moon itself, like tapping on it in the Camera app.
    /// Without this the camera brightens for the dark sky and the moon becomes a soft, blown-out glow.
    private func aim(at point: CGPoint?) {
        guard Date().timeIntervalSince(lastAim) > 0.8, !busy else { return }
        if let p = point, let a = aimedAt, hypot(p.x - a.x, p.y - a.y) < 0.03 { return }   // already aimed here
        if point == nil && aimedAt == nil { return }
        lastAim = Date()
        sessionQueue.async {
            guard let d = self.device, (try? d.lockForConfiguration()) != nil else { return }
            let target = point ?? CGPoint(x: 0.5, y: 0.5)
            if d.isExposurePointOfInterestSupported { d.exposurePointOfInterest = target }
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = target }
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            d.unlockForConfiguration()
            self.aimedAt = point
        }
    }
}

// MARK: - Photo capture delegate that hands back the file data

final class PhotoCatcher: NSObject, AVCapturePhotoCaptureDelegate {
    private let done: (Data?, PhotoCatcher) -> Void
    init(done: @escaping (Data?, PhotoCatcher) -> Void) { self.done = done }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        done(error == nil ? photo.fileDataRepresentation() : nil, self)
    }
}

/// Picks the moon frame that kept the most real detail: the brightest one that is not blown out
enum MoonCameraPick {
    struct Frame { let data: Data; let label: String; let offset: Double }
    static func best(_ frames: [Frame]) -> Frame? {
        let scored = frames.compactMap { f -> (Frame, Double)? in
            guard let c = MoonBlend.moonClip(f.data) else { return nil }
            // brighter is better (less grain) until highlights start to clip; clipping is punished hard
            return (f, c.peak / 255 - 6 * c.clipped)
        }
        return scored.max { $0.1 < $1.1 }?.0 ?? frames.first
    }
}
