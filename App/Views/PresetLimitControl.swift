import SwiftUI

struct PresetLimitControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: String

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(valueLabel).font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(Color.accentColor)
            }
            HStack(spacing: 10) {
                Button { value = max(range.lowerBound, value - step) } label: {
                    Image(systemName: "minus").frame(width: 18, height: 18)
                }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel(String(format: String(localized: "Decrease %@"), title))
                Slider(value: $value, in: range, step: step)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueLabel)
                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus").frame(width: 18, height: 18)
                }
                .disabled(value >= range.upperBound)
                .accessibilityLabel(String(format: String(localized: "Increase %@"), title))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
