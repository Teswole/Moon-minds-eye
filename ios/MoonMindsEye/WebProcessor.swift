// 2026-11-14 3:45 PM CST — Runs the tested Moon Mind's Eye photo processor (moon rebuild, sky AI, mind's-eye sky) inside the app
import Foundation
import WebKit
import SwiftUI

/// Serves the bundled web files (index.html, moon maps) to the hidden web view under mme://app/
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let relative = String(path.dropFirst())
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("Web", isDirectory: true),
              !relative.contains(".."),
              let data = try? Data(contentsOf: base.appendingPathComponent(relative)) else {
            task.didFailWithError(NSError(domain: "mme", code: 404))
            return
        }
        let mime: String
        switch (relative as NSString).pathExtension.lowercased() {
        case "html": mime = "text/html; charset=utf-8"
        case "png": mime = "image/png"
        case "js": mime = "text/javascript"
        case "json": mime = "application/json"
        default: mime = "application/octet-stream"
        }
        let headers = ["Content-Type": mime, "Access-Control-Allow-Origin": "*", "Content-Length": "\(data.count)"]
        if let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) {
            task.didReceive(resp)
        }
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@MainActor
final class WebProcessor: NSObject, WKNavigationDelegate {
    static let shared = WebProcessor()

    let webView: WKWebView
    private var ready = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    struct Result {
        let jpeg: Data?
        let found: Bool
        let checks: String
        let size: String
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: "mme")
        config.userContentController.addUserScript(
            WKUserScript(source: "window.MME_NATIVE=true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init()
        webView.navigationDelegate = self
        if let url = URL(string: "mme://app/index.html") { webView.load(URLRequest(url: url)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.ready = true
            self.waiters.forEach { $0.resume() }
            self.waiters.removeAll()
        }
    }

    private func waitUntilReady() async {
        if ready { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }

    /// Hands one photo to the processor; returns the finished mind's-eye picture.
    func process(_ jpeg: Data, lat: Double?, lng: Double?, when: Date,
                 rebuild: Bool, mindsEyeSky: Bool, aiSky: Bool) async throws -> Result {
        await waitUntilReady()
        var opts: [String: Any] = [
            "rebuildChk": rebuild, "skyChk": mindsEyeSky, "aiSkyChk": aiSky,
            "when": when.timeIntervalSince1970 * 1000
        ]
        if let lat = lat, let lng = lng { opts["lat"] = lat; opts["lng"] = lng }
        let value = try await webView.callAsyncJavaScript(
            "return await window.mmeProcess(b64, opts);",
            arguments: ["b64": jpeg.base64EncodedString(), "opts": opts],
            in: nil, contentWorld: .page)
        guard let dict = value as? [String: Any] else {
            return Result(jpeg: nil, found: false, checks: "Processor didn't answer", size: "")
        }
        let data = (dict["jpeg"] as? String).flatMap { Data(base64Encoded: $0) }
        return Result(jpeg: data, found: dict["found"] as? Bool ?? false,
                      checks: dict["checks"] as? String ?? "", size: dict["size"] as? String ?? "")
    }
}

/// Keeps the hidden web view inside the app's window so the phone runs it at full speed
struct WebProcessorHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        holder.isUserInteractionEnabled = false
        holder.clipsToBounds = true
        let web = WebProcessor.shared.webView
        web.removeFromSuperview()
        holder.addSubview(web)
        return holder
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
