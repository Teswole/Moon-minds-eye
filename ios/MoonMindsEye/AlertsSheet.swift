// 2026-11-20 10:40 PM CST — Big-moon alerts screen (opened from the page's "Set up alerts" button)
import SwiftUI

struct AlertsSheet: View {
    @EnvironmentObject var location: LocationModel
    @EnvironmentObject var alerts: MoonAlerts
    @Environment(\.dismiss) private var dismiss
    private let gold = Color(red: 0.96, green: 0.78, blue: 0.42)

    var body: some View {
        NavigationStack {
            ScrollView {
                if let c = location.coordinate {
                    alertCard(lat: c.latitude, lng: c.longitude).padding()
                        .onAppear { alerts.refresh(lat: c.latitude, lng: c.longitude) }
                } else {
                    Text("Allow location for Moon Mind's Eye so it knows where the moon will be.").padding()
                }
            }
            .navigationTitle("Big-moon alerts").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(gold) } }
        }
        .preferredColorScheme(.dark)
    }

    func alertCard(lat: Double, lng: Double) -> some View {
        let day = DateFormatter(); day.dateFormat = "EEE MMM d"
        let t = DateFormatter(); t.dateFormat = "h:mm a"
        let redo = { alerts.refresh(lat: lat, lng: lng) }
        return card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Big-moon alerts").font(.headline)
                Text("Your phone buzzes before each low-moon window. Only your phone gets them.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Alert me", isOn: Binding(get: { alerts.on }, set: { alerts.on = $0; redo() })).tint(gold)
                Picker("How early", selection: Binding(get: { alerts.lead }, set: { alerts.lead = $0; redo() })) {
                    Text("5 minutes before").tag(5); Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30); Text("1 hour before").tag(60)
                }
                .pickerStyle(.menu).disabled(!alerts.on)
                Toggle("Only nights at least 40% lit", isOn: Binding(get: { alerts.brightOnly }, set: { alerts.brightOnly = $0; redo() }))
                    .tint(gold).font(.subheadline)
                if alerts.on && alerts.armed {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alerts are ON").bold()
                            if let n = alerts.nextAlert { Text("Next alert: \(day.string(from: n)) at \(t.string(from: n))").font(.footnote) }
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                } else if alerts.on && !alerts.blocked {
                    HStack { ProgressView(); Text("Setting up alerts…").font(.footnote) }
                } else if !alerts.on {
                    HStack { Image(systemName: "bell.slash").foregroundStyle(.secondary); Text("Alerts are off").font(.footnote).foregroundStyle(.secondary) }
                }
                if !alerts.note.isEmpty && !(alerts.on && !alerts.armed && !alerts.blocked) { Text(alerts.note).font(.footnote).foregroundStyle(alerts.blocked ? .orange : .secondary) }
                Button(alerts.testSent ? "✓ Test sent. Watch for it in 5 seconds" : "Send me a test alert") { alerts.sendTest() }
                    .font(.subheadline.bold()).foregroundStyle(alerts.testSent ? .green : gold)
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

    func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
