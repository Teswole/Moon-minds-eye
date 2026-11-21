// 2026-11-20 10:40 PM CST — One app: the full Moon Mind's Eye page, with the pro camera and phone alerts built in
import SwiftUI
import WebKit
import CoreLocation

/// Lets the page ask the app for things only the app can do
final class AppNav: ObservableObject {
    @Published var showCamera = false
    @Published var showAlerts = false
}

/// The full Moon Mind's Eye page (same as the website, always up to date). Falls back to the copy inside the app when offline.
struct WebShell: UIViewRepresentable {
    @ObservedObject var nav: AppNav
    let coordinate: CLLocationCoordinate2D?
    static let live = URL(string: "https://moon-minds-eye.onrender.com/?app=1")!
    static let bundled = URL(string: "mme://app/index.html?app=1")!

    func makeCoordinator() -> Coord { Coord(nav: nav) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: "mme")
        cfg.userContentController.add(context.coordinator, name: "mme")
        cfg.userContentController.addUserScript(WKUserScript(source: "window.MME_APP=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.allowsBackForwardNavigationGestures = false
        context.coordinator.web = web
        var req = URLRequest(url: Self.live); req.timeoutInterval = 12
        web.load(req)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if let c = coordinate { context.coordinator.send(c) }
    }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let nav: AppNav
        weak var web: WKWebView?
        private var sent: CLLocationCoordinate2D?
        private var loaded = false
        private var triedBundle = false
        init(nav: AppNav) { self.nav = nav }

        /// Messages from the page: "camera" opens the pro camera, "alerts" opens phone alerts
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            switch m.body as? String {
            case "camera": DispatchQueue.main.async { self.nav.showCamera = true }
            case "alerts": DispatchQueue.main.async { self.nav.showAlerts = true }
            default: break
            }
        }

        /// Give the page the phone's location so it never has to ask
        func send(_ c: CLLocationCoordinate2D) {
            guard loaded, let web = web else { sent = nil; pending = c; return }
            if let s = sent, abs(s.latitude - c.latitude) < 0.01, abs(s.longitude - c.longitude) < 0.01 { return }
            sent = c
            web.evaluateJavaScript("window.mmeAppLoc && window.mmeAppLoc(\(c.latitude), \(c.longitude))")
        }
        private var pending: CLLocationCoordinate2D?

        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            loaded = true; if let p = pending { pending = nil; send(p) }
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { fallback(w) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { fallback(w) }
        private func fallback(_ w: WKWebView) {   // no internet: use the copy inside the app
            guard !triedBundle else { return }; triedBundle = true; loaded = false; w.load(URLRequest(url: WebShell.bundled))
        }

        /// Links to other websites open in Safari
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if a.navigationType == .linkActivated, let u = a.request.url, u.host != "moon-minds-eye.onrender.com", u.scheme != "mme" {
                UIApplication.shared.open(u); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}

struct AppShell: View {
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var camera: CameraModel
    @EnvironmentObject var alerts: MoonAlerts
    @StateObject private var nav = AppNav()
    var body: some View {
        WebShell(nav: nav, coordinate: location.coordinate)
            .ignoresSafeArea(edges: .bottom)
            .background(Color(red: 0.03, green: 0.04, blue: 0.09).ignoresSafeArea())
            .fullScreenCover(isPresented: $nav.showCamera) { CameraView(onClose: { nav.showCamera = false }).environmentObject(location).environmentObject(camera).environmentObject(alerts) }
            .sheet(isPresented: $nav.showAlerts) { AlertsSheet().environmentObject(location).environmentObject(alerts) }
    }
}
