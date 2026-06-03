import SwiftUI

struct SettingsView: View {
    let store: ThermalStatusStore

    var body: some View {
        Form {
            Section("采样") {
                Picker("温度/风扇", selection: Binding(
                    get: { store.sampleIntervalSeconds },
                    set: { store.setSampleInterval($0) }
                )) {
                    Text("1 秒").tag(1)
                    Text("3 秒").tag(3)
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                }
                .pickerStyle(.segmented)

                LabeledContent("网速") {
                    Text("1 秒")
                        .foregroundStyle(.secondary)
                }
            }

            Section("状态栏显示") {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(metric.title, isOn: Binding(
                        get: { store.isMenuBarMetricSelected(metric) },
                        set: { store.setMenuBarMetric(metric, enabled: $0) }
                    ))
                }

                Text("勾选的指标会按顺序显示在菜单栏标题里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("当前标题") {
                    Text(store.menuBarTitle)
                        .monospacedDigit()
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("本机采集") {
                LabeledContent("状态") {
                    Text(store.helperState.title)
                }
            }
        }
        .padding(20)
    }
}
