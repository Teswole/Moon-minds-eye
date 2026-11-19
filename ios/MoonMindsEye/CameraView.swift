// 2026-11-18 10:30 PM CST — Camera tab: live view, lens buttons, shutter, mind's-eye options and the result screen
import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject var camera: CameraModel
    @EnvironmentObject var location: LocationModel
    @State private var showOptions = false
    @StateObject private var coach = ShotCoach()
    @State private var live = false          // camera starts only when the person taps Start
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.42)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WebProcessorHost().frame(width: 2, height: 2).opacity(0.01).allowsHitTesting(false)
            if !live { intro } else {
            PreviewView(session: camera.session, moonPoint: camera.moonPoint)
                .ignoresSafeArea(edges: .top)
            VStack {
                HStack {
                    Button(action: { coach.end(); camera.stop(); live = false }) {
                        Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }.accessibilityLabel("Stop camera and show tips")
                    Spacer()
                    Text(camera.moonPoint == nil ? camera.status : "Moon locked ✓")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16).padding(.top, 12)
                Spacer()
                if camera.lenses.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(camera.lenses) { lens in
                            Button(lens.label) { camera.selectLens(lens.id) }
                                .font(.footnote.bold())
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(camera.currentLensID == lens.id ? gold : Color.black.opacity(0.5), in: Capsule())
                                .foregroundStyle(camera.currentLensID == lens.id ? Color.black : Color.white)
                        }
                    }
                }
                CoachCard(coach: coach).padding(.bottom, 6)
                HStack {
                    thumbnail.frame(width: 56, height: 56)
                    Spacer()
                    Button(action: {
                        camera.captureMindsEye(lat: location.coordinate?.latitude, lng: location.coordinate?.longitude)
                    }) {
                        ZStack {
                            Circle().fill(.white).frame(width: 74, height: 74)
                            Circle().stroke(gold, lineWidth: 6).frame(width: 86, height: 86)
                            if camera.busy { ProgressView().tint(.black) }
                        }
                    }
                    .disabled(camera.busy)
                    .accessibilityLabel("Take mind's-eye photo")
                    Spacer()
                    Button(action: { showOptions = true }) {
                        Image(systemName: "slider.horizontal.3").font(.title2)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Mind's-eye options")
                }
                .padding(.horizontal, 30)
                Color.clear.frame(height: 10)
            }
            .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showOptions) { OptionsSheet().environmentObject(camera).presentationDetents([.medium]) }
        .sheet(isPresented: $camera.showResult) { ResultSheet().environmentObject(camera) }
        .onDisappear { coach.end(); camera.stop(); live = false }
    }

    /// Tips screen shown first, so there is time to read before the camera turns on
    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "camera.aperture").font(.system(size: 44)).foregroundStyle(gold)
                    .frame(maxWidth: .infinity)
                Text("Mind's-eye camera").font(.title.bold()).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    tip("1.circle.fill", "Tap **Start camera** and allow camera access if asked.")
                    tip("2.circle.fill", "Point at the moon. **Moon locked ✓** means it found it.")
                    tip("3.circle.fill", "Tap **Zoom lens** if you have one, and keep trees or rooftops in the picture.")
                    tip("4.circle.fill", "**Step back** from the trees and houses. The farther away they are, the bigger the moon looks next to them.")
                    tip("5.circle.fill", "**Hold still.** The steps at the bottom check themselves off, and the camera counts 3-2-1 and takes the photo for you.")
                    tip("moon.stars.fill", "Best when the moon is low (under about 10°). Check the green window on the Moon tab.")
                }
                .font(.body)
                Button(action: { live = true; camera.start(); coach.begin(camera: camera, lat: location.coordinate?.latitude, lng: location.coordinate?.longitude) }) {
                    Text("Start camera").font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(gold, in: Capsule())
                }
                .padding(.top, 8)
                if camera.lastResult != nil {
                    Button("See last photo") { camera.showResult = true }
                        .frame(maxWidth: .infinity).foregroundStyle(gold)
                }
            }
            .padding(24).padding(.top, 30)
            .foregroundStyle(.white)
        }
    }

    private func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(gold).font(.title3).frame(width: 28)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let img = camera.lastResult {
            Button(action: { camera.showResult = true }) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 2))
            }
            .accessibilityLabel("Show last photo")
        } else {
            RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.3), lineWidth: 2)
        }
    }
}

/// Live camera view, with a gold ring over the moon when it's found
struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let moonPoint: CGPoint?

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let ring = CAShapeLayer()
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        v.ring.strokeColor = UIColor(red: 0.96, green: 0.78, blue: 0.42, alpha: 1).cgColor
        v.ring.fillColor = UIColor.clear.cgColor
        v.ring.lineWidth = 4                     // solid and thick so it is easy to see over a bright moon
        v.ring.shadowColor = UIColor.black.cgColor; v.ring.shadowOpacity = 0.8; v.ring.shadowRadius = 3; v.ring.shadowOffset = .zero
        v.layer.addSublayer(v.ring)
        return v
    }

    func updateUIView(_ v: PreviewUIView, context: Context) {
        guard let p = moonPoint else { v.ring.path = nil; return }
        // the moon finder works in camera-sensor coordinates; convert to the screen
        let screen = v.preview.layerPointConverted(fromCaptureDevicePoint: p)
        v.ring.path = UIBezierPath(ovalIn: CGRect(x: screen.x - 44, y: screen.y - 44, width: 88, height: 88)).cgPath
    }
}

/// Switches for the mind's-eye processing
struct OptionsSheet: View {
    @EnvironmentObject var camera: CameraModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Moon exposure while aiming", isOn: $camera.moonExposure)
                    Toggle("Rebuild the moon in full detail", isOn: $camera.rebuildMoon)
                    Toggle("Brighten the night sky to twilight blue", isOn: $camera.mindsEyeSky)
                    Toggle("AI sky detection", isOn: $camera.aiSky)
                } footer: {
                    Text("AI sky detection downloads a small model the first time it's used (Wi-Fi is best). Your photos stay on your phone.")
                }
            }
            .navigationTitle("Mind's-eye options")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The finished picture, with a press-and-hold "before" view
struct ResultSheet: View {
    @EnvironmentObject var camera: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var showBefore = false
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.42)

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let img = (showBefore ? camera.lastBefore : camera.lastResult) ?? camera.lastResult {
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topLeading) {
                            Text(showBefore ? "Camera saw" : "Mind's eye")
                                .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(showBefore ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(gold), in: Capsule())
                                .foregroundStyle(showBefore ? Color.white : Color.black)
                                .padding(10)
                        }
                        .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 50, pressing: { showBefore = $0 }, perform: {})
                }
                Text("Press and hold the picture to see what the camera saw").font(.caption).foregroundStyle(.secondary)
                Text(camera.lastChecks).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Text("Saved to Photos. This is an edited picture: the moon is enlarged and its detail comes from the camera when it caught it, or from the app's moon map at tonight's phase.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Your mind's-eye moon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
