import SwiftUI

struct FanTelemetryView: View {
    let store: FanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(store.rpmLabel).font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                Text("RPM").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let temperature = store.snapshot?.temperature {
                    Label("\(Int(temperature.rounded())) °C", systemImage: "thermometer.medium")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .help("Highest available CPU or GPU sensor temperature")
                }
            }
            if let snapshot = store.snapshot {
                ForEach(snapshot.fans) { fan in
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: min(fan.rpm / fan.limits.maximum, 1))
                            .tint(Color.accentColor)
                        HStack {
                            Text(snapshot.fans.count == 1 ? String(localized: "Fan") : String(format: String(localized: "Fan %d"), fan.id + 1))
                            Spacer()
                            Text("\(Int(fan.rpm)) / \(Int(fan.limits.maximum)) RPM").monospacedDigit()
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(store.sensorError == nil ? String(localized: "Reading fan…") : String(localized: "Reading unavailable"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

}
