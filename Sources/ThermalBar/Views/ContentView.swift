import SwiftUI

struct ContentView: View {
    let store: ThermalStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("ThermalBar")
                    .font(.largeTitle.bold())
                Spacer()
                Text(store.helperState.title)
                    .foregroundStyle(stateColor)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "电池温度", value: Formatters.temperature(store.status?.batteryTemperatureC))
                StatCard(title: "虚拟温度", value: Formatters.temperature(store.status?.virtualTemperatureC))
                StatCard(title: "风扇转速", value: Formatters.fanSpeed(store.status?.fanRPM))
                StatCard(title: "下载速度", value: Formatters.networkSpeed(store.networkDownloadBps))
                StatCard(title: "上传速度", value: Formatters.networkSpeed(store.networkUploadBps))
                StatCard(title: "CPU 使用率", value: Formatters.percent(store.cpuUsagePercent))
                StatCard(title: "CPU 温度", value: Formatters.temperature(store.status?.cpuTemperatureC))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("原始摘要")
                    .font(.headline)
                ScrollView {
                    Text(store.status?.rawSummary ?? store.lastReadError ?? "暂无采集数据。")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120)
            }

            HStack {
                Text("最后更新：\(Formatters.date(store.status?.timestamp))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刷新") {
                    store.refresh()
                }
            }
        }
        .padding(24)
    }

    private var stateColor: Color {
        switch store.helperState {
        case .running:
            .green
        case .stale:
            .orange
        case .failed, .notInstalled:
            .red
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
