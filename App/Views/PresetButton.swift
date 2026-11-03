import BreezeCore
import SwiftUI

struct PresetButton: View {
    let preset: FanPreset
    let configuration: PresetConfiguration
    let selected: Bool
    let action: () -> Void

    private var detail: String {
        if preset == .standard { return String(localized: "Managed by macOS.") }
        return String(format: String(localized: "From %d%% · maximum at %d °C"), Int(configuration.minimumFraction * 100), Int(configuration.fullTemperature))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 28)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(selected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.035), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.04), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title), \(detail)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
