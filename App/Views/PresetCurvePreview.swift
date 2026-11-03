import BreezeCore
import Charts
import SwiftUI

struct PresetCurvePreview: View {
    let configuration: PresetConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Warming", systemImage: "arrow.up.right").foregroundStyle(Color.accentColor)
                Spacer()
                Label("Cooling", systemImage: "arrow.down.right").foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: .medium))
            Chart {
                ForEach(0..<2) { direction in
                    ForEach(Array(stride(from: 20.0, through: 90.0, by: 1)), id: \.self) { temperature in
                        LineMark(
                            x: .value("Temperature", temperature),
                            y: .value("Speed", configuration.fraction(at: temperature + (direction == 1 ? configuration.hysteresis : 0)) * 100),
                            series: .value("Direction", direction)
                        )
                        .foregroundStyle(direction == 0 ? Color.accentColor : Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: direction == 0 ? [] : [4, 3]))
                    }
                }
            }
            .chartXScale(domain: 20...90)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [20, 40, 60, 80]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let temperature = value.as(Int.self) { Text("\(temperature) °C") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let speed = value.as(Int.self) { Text("\(speed)%") }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 100)
            .accessibilityLabel("Preset curve")
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 12))
    }
}
