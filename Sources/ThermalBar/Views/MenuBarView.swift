import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let store: ThermalStatusStore
    var openDetails: (() -> Void)?
    var openSettingsAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Divider()
            metricRows
            Divider()
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 260)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.helperState.title)
                .font(.headline)
            Text("更新于 \(Formatters.age(store.status?.timestamp))")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var metricRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            MetricRow(title: "电池温度", value: Formatters.temperature(store.status?.batteryTemperatureC))
            MetricRow(title: "虚拟温度", value: Formatters.temperature(store.status?.virtualTemperatureC))
            MetricRow(title: "系统功耗", value: Formatters.power(store.status?.systemPowerW))
            MetricRow(title: "风扇转速", value: Formatters.fanSpeed(store.status?.fanRPM))
            MetricRow(title: "下载速度", value: Formatters.networkSpeed(store.networkDownloadBps))
            MetricRow(title: "上传速度", value: Formatters.networkSpeed(store.networkUploadBps))
            MetricRow(title: "CPU 使用率", value: Formatters.percent(store.cpuUsagePercent))
            MetricRow(title: "CPU 温度", value: Formatters.temperature(store.status?.cpuTemperatureC))
            MetricRow(title: "CPU", value: Formatters.power(store.status?.cpuPowerW))
            MetricRow(title: "GPU", value: Formatters.power(store.status?.gpuPowerW))
            MetricRow(title: "ANE", value: Formatters.power(store.status?.anePowerW))
            MetricRow(title: "热压力", value: store.status?.thermalPressure ?? "—")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button("打开详情") {
                if let openDetails {
                    openDetails()
                } else {
                    openWindow(id: "details")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Button("立即刷新") {
                store.refresh()
            }
            Button("安装辅助服务") {
                store.installHelper()
            }
            Button("卸载辅助服务") {
                store.uninstallHelper()
            }
            Button("设置") {
                if let openSettingsAction {
                    openSettingsAction()
                } else {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .frame(height: 18)
    }
}
