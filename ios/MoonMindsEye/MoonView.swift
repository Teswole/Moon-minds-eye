// 2026-11-20 2:25 AM CST — Moon tab: tonight's moon, where to look, and the next big-moon window
import SwiftUI

struct MoonView: View {
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var alerts: MoonAlerts
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.42)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.07), Color(red: 0.07, green: 0.09, blue: 0.2)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Moon Mind's Eye").font(.system(size: 28, weight: .bold, design: .rounded)).padding(.top, 24)
                    if let c = location.coordinate {
                        let m = MoonMath.moon(now, lat: c.latitude, lng: c.longitude)
                        let sun = MoonMath.sunAltitude(now, lat: c.latitude, lng: c.longitude)
                        Text(MoonMath.phaseName(m)).font(.title2.bold())
                        HStack(spacing: 10) {
                            stat(String(format: "%.1f°", m.altitude), "Above horizon")
                            stat("\(Int(m.bearing.rounded()))° \(MoonMath.compass(m.bearing))", "Heading")
                            stat("\(Int((m.fraction * 100).rounded()))%", "Lit")
                        }
                        zoneCard(m, sun: sun, lat: c.latitude, lng: c.longitude)
                        alertCard(lat: c.latitude, lng: c.longitude)
                    } else if location.denied {
                        card { Text("Location is off. Turn it on in Settings → Moon Mind's Eye → Location, so the app can find the moon in your sky.") }
                    } else {
                        ProgressView("Finding your location…").padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .foregroundStyle(.white)
        .onReceive(timer) { now = $0 }
        .onAppear { if let c = location.coordinate { alerts.refresh(lat: c.latitude, lng: c.longitude) } }
        .onChange(of: location.coordinate?.latitude) { _, _ in if let c = location.coordinate { alerts.refresh(lat: c.latitude, lng: c.longitude) } }
    }

    private func zoneCard(_ m: MoonState, sun: Double, lat: Double, lng: Double) -> some View {
        let status: (String, Color) = {
            if m.altitude < 0 { return ("Below the horizon", .gray) }
            if m.altitude <= 10 { return (sun < 2 ? "Illusion zone · shoot now" : "Low, but the sky is still bright", sun < 2 ? .green : .orange) }
            if m.altitude <= 20 { return ("Getting high; the illusion is fading", .orange) }
            return ("Too high for the big-moon look", .gray)
        }()
        let window = MoonMath.nextWindow(from: now, lat: lat, lng: lng)
        let fmt = DateFormatter(); fmt.dateFormat = "EEE h:mm a"
        return card {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Circle().fill(status.1).frame(width: 9, height: 9); Text(status.0).bold() }
                if let w = window {
                    Text("Best window: \(fmt.string(from: w.start))\(w.end.map { " – " + fmt.string(from: $0) } ?? "")")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No low-moon window in the next 2 days").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Big-moon alerts: notifications from this app, only on this phone (no calendar invites)
    private func alertCard(lat: Double, lng: Double) -> some View {
        let day = DateFormatter(); day.dateFormat = "EEE MMM d"
        let t = DateFormatter(); t.dateFormat = "h:mm a"
        let redo = { alerts.refresh(lat: lat, lng: lng) }
        return card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Big-moon alerts").font(.headline)
                Text("Your phone buzzes before each low-moon window. Only you get them; nothing goes to a calendar.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Alert me", isOn: Binding(get: { alerts.on }, set: { alerts.on = $0; redo() })).tint(gold)
                Picker("How early", selection: Binding(get: { alerts.lead }, set: { alerts.lead = $0; redo() })) {
                    Text("5 minutes before").tag(5); Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30); Text("1 hour before").tag(60)
                }
                .pickerStyle(.menu).disabled(!alerts.on)
                Toggle("Only nights at least 40% lit", isOn: Binding(get: { alerts.brightOnly }, set: { alerts.brightOnly = $0; redo() }))
                    .tint(gold).font(.subheadline)
                if !alerts.note.isEmpty { Text(alerts.note).font(.footnote).foregroundStyle(alerts.blocked ? .orange : .secondary) }
                if alerts.blocked {
                    Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                        .font(.subheadline.bold()).foregroundStyle(gold)
                }
                ForEach(Array(alerts.upcoming.prefix(4).enumerated()), id: \.offset) { _, w in
                    HStack {
                        Text(day.string(from: w.start)).bold()
                        Spacer()
                        Text("\(t.string(from: w.start))–\(t.string(from: w.end)) · \(w.lit)% · \(w.dir)").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
