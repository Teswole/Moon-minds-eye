// 2026-11-14 8:20 PM CST — Camera tab: live view, lens buttons, shutter, mind's-eye options and the result screen
import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject var camera: CameraModel
    @EnvironmentObject var location: LocationModel
    @State private var showOptions = false
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.42)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WebProcessorHost().frame(width: 2, height: 2).opacity(0.01).allowsHitTesting(false)
            PreviewView(session: camera.session, moonPoint: camera.moonPoint)
                .ignoresSafeArea(edges: .top)
            VStack {
                Text(camera.moonPoint == nil ? camera.status : "Moon locked ✓")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
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
                Toggle("Moon exposure while aiming", isOn: $camera.moonExposure)
                    .font(.footnote).padding(.horizontal, 40).padding(.top, 6)
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
                Text("One tap takes two exposures: one for the scene, one for the moon")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 14)
            }
            .foregroundStyle(.white)
        }
        .sheet(isPresented: $showOptions) { OptionsSheet().environmentObject(camera).presentationDetents([.medium]) }
        .sheet(isPresented: $camera.showResult) { ResultSheet().environmentObject(camera) }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
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
        v.ring.lineWidth = 2
        v.ring.lineDashPattern = [3, 6]
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
                Text("Saved to Photos. This is an edited picture: the moon is enlarged and its detail comes from the app's moon map at tonight's phase.")
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
