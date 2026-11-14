// 2026-11-14 3:10 PM CST — Camera tab: live view with moon marker, lens buttons and the shutter
import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject var camera: CameraModel
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.42)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
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
                    Button(action: { camera.captureMindsEye() }) {
                        ZStack {
                            Circle().fill(.white).frame(width: 74, height: 74)
                            Circle().stroke(gold, lineWidth: 6).frame(width: 86, height: 86)
                            if camera.busy { ProgressView().tint(.black) }
                        }
                    }
                    .disabled(camera.busy)
                    .accessibilityLabel("Take mind's-eye photo")
                    Spacer()
                    Color.clear.frame(width: 56, height: 56)
                }
                .padding(.horizontal, 30)
                Text("One tap takes two exposures: one for the scene, one for the moon")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 14)
            }
            .foregroundStyle(.white)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder private var thumbnail: some View {
        if let img = camera.lastResult {
            Image(uiImage: img).resizable().scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 2))
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
