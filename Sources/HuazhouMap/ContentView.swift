import SwiftUI
import HuazhouCore

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 300, idealWidth: 330, maxWidth: 460)
            MapPane()
                .frame(minWidth: 480)
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}

// MARK: - 侧栏

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $state.sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            switch state.sidebarTab {
            case .points: pointList
            case .segments: segmentList
            case .settings: settingsList
            }

            Divider()
            actionBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("工程名称", text: $state.project.name)
                .textFieldStyle(.roundedBorder)
                .font(.headline)

            HStack {
                Toggle("点击地图打点", isOn: $state.addMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Text("\(state.chain.pointCount) 点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("成链方式", selection: $state.project.chainMode) {
                ForEach(ChainMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(12)
    }

    private var pointList: some View {
        List(selection: $state.selection) {
            ForEach(Array(state.chain.orderedPoints.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    TextField("点名", text: nameBinding(for: point))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Spacer(minLength: 4)
                    Text(segmentLengthText(at: index))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .tag(point.id)
            }
        }
        .onDeleteCommand { state.deleteSelected() }
    }

    private var segmentList: some View {
        Group {
            if state.chain.segments.isEmpty {
                emptyHint("打两个点以上才会生成分段")
            } else {
                List {
                    ForEach(state.chain.segments) { segment in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(segment.index). \(segment.fromName) → \(segment.toName)")
                                    .font(.callout)
                                Spacer()
                                Text(String(format: "%.2f m", segment.length))
                                    .font(.callout.monospacedDigit())
                            }
                            Text(String(format: "累计 %.1f m ｜ 方位 %@", segment.cumulative, segment.azimuthText))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var settingsList: some View {
        Form {
            Section("出图坐标系") {
                Picker("坐标系", selection: $state.project.projection.kind) {
                    ForEach(ProjectionKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                TextField("中央子午线（留空自动分带）", text: $state.centralMeridianText)
                    .textFieldStyle(.roundedBorder)
                Text(zoneDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("杆符号半径 (m)", value: $state.poleRadius, format: .number)
                        .textFieldStyle(.roundedBorder)
                    TextField("文字高度 (m)", value: $state.textHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("标注段长", isOn: $state.showSegmentLength)
            }

            Section("地图") {
                Picker("底图", selection: $state.mapStyle) {
                    ForEach(MapStyleChoice.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Toggle("使用自定义瓦片服务", isOn: $state.useCustomTiles)
                TextField("瓦片 URL 模板", text: $state.customTileURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!state.useCustomTiles)
                Text("模板占位符：{z} {x} {y}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    state.exportDXF()
                } label: {
                    Label("导出 DXF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    state.exportCSV()
                } label: {
                    Label("点表 CSV", systemImage: "tablecells")
                }
            }
            HStack(spacing: 8) {
                Button {
                    state.deleteSelected()
                } label: {
                    Label("删除选中", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(state.selection == nil)

                Button {
                    state.clearAll()
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
                .disabled(state.project.points.isEmpty)
            }
        }
        .padding(12)
    }

    // MARK: - 辅助

    private var zoneDescription: String {
        guard let projector = state.projector else {
            return "尚无点位，坐标系参数将在打点后生效"
        }
        if let zone = projector.zone, let meridian = projector.effectiveMeridian {
            return String(format: "当前：第 %d 带，中央子午线 %g°", zone, meridian)
        }
        return "当前：以首点为原点"
    }

    private func nameBinding(for point: SurveyPoint) -> Binding<String> {
        Binding(
            get: { state.project.points.first(where: { $0.id == point.id })?.name ?? point.name },
            set: { state.renamePoint(id: point.id, to: $0) }
        )
    }

    private func segmentLengthText(at index: Int) -> String {
        guard index > 0, index - 1 < state.chain.segments.count else { return "—" }
        return String(format: "%.1f m", state.chain.segments[index - 1].length)
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 地图与状态栏

struct MapPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SurveyMapView(state: state)
            Divider()
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label("\(state.chain.pointCount) 点", systemImage: "mappin.and.ellipse")
            Text(String(format: "总长 %.1f m", state.chain.totalLength))
                .monospacedDigit()
            if !state.chain.segments.isEmpty {
                Text(String(format: "平均段长 %.1f m", state.chain.averageSegment))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 14)

            if let point = state.selectedPoint {
                Text("\(point.name)  \(point.coordinate.dms)")
                    .monospacedDigit()
                if let plan = state.projector?.project(point.coordinate).plan {
                    Text(String(format: "N %.3f  E %.3f", plan.northing, plan.easting))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("未选中点位").foregroundStyle(.secondary)
            }

            Spacer()
            Text(state.message).lineLimit(1).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
