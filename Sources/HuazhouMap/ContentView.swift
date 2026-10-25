import SwiftUI
import HuazhouCore
import HuazhouAppCore

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 310, idealWidth: 340, maxWidth: 480)
            MapPane()
                .frame(minWidth: 420)
        }
        .frame(minWidth: 900, minHeight: 480)
        .task { state.loadStartupProjectFromCommandLine() }
        .sheet(isPresented: $state.showManualEntry) {
            ManualEntryView()
                .environmentObject(state)
        }
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

            Group {
                switch state.sidebarTab {
                case .points: pointList
                case .segments: segmentList
                case .settings: settingsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            actionBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("工程名称", text: $state.project.name)
                .textFieldStyle(.roundedBorder)
                .font(.headline)

            HStack(spacing: 8) {
                Toggle("点击地图打点", isOn: $state.addMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Picker("", selection: $state.activeKind) {
                    ForEach(ObjectKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                .frame(width: 90)
            }

            HStack(spacing: 8) {
                Picker("", selection: $state.project.chainMode) {
                    ForEach(ChainMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                Spacer()
                Text("\(state.chain.pointCount) 点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var pointList: some View {
        List(selection: $state.selection) {
            ForEach(Array(state.chain.orderedPoints.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 6) {
                    Menu {
                        ForEach(ObjectKind.allCases, id: \.self) { kind in
                            Button(kind.displayName) { state.setKind(id: point.id, kind: kind) }
                        }
                    } label: {
                        Circle()
                            .fill(color(for: point.kind))
                            .frame(width: 9, height: 9)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 14)

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
                Menu("填入瓦片源预设") {
                    ForEach(TilePreset.all) { preset in
                        Button(preset.name) {
                            state.customTileURL = preset.template
                            state.useCustomTiles = true
                            state.project.applyGCJCorrection = preset.needsCorrection
                        }
                    }
                }
                .controlSize(.small)
                Toggle("显示坐标按 GCJ-02 纠偏", isOn: $state.project.applyGCJCorrection)
                Text("高德/腾讯瓦片需要纠偏；Apple 底图与天地图不需要")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    state.exportDXF()
                } label: {
                    Label("导出 DXF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button("点表 CSV…") { state.exportCSV() }
                    Button("KML（Google Earth/手机）…") { state.exportKML() }
                    Button("GPX（测绘/运动设备）…") { state.exportGPX() }
                } label: {
                    Label("格式", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 72)
            }

            HStack(spacing: 8) {
                Button {
                    state.showManualEntry = true
                } label: {
                    Label("手动输入", systemImage: "plus.circle").frame(maxWidth: .infinity)
                }

                Menu {
                    Button("从 CSV 导入…") { state.importCSV() }
                    Button("从 KML 导入…") { state.importKML() }
                } label: {
                    Label("导入", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)

                Button {
                    state.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(state.selection == nil)
                .help("删除选中点位（⌫）")

                Button {
                    state.clearAll()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(state.project.points.isEmpty)
                .help("清空工程")
            }
        }
        .padding(10)
        .layoutPriority(1)
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

    private func color(for kind: ObjectKind) -> Color {
        switch kind {
        case .pole: return .red
        case .manhole: return .blue
        case .joint: return .purple
        case .marker: return .orange
        case .crossing: return .teal
        case .station: return .green
        case .other: return .gray
        }
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

// MARK: - 手动输入

/// 手动输入表单的本地状态。
/// 注意：本机只装了 Command Line Tools 时 `@State`（宏实现）无法加载，
/// 因此统一用 `@StateObject` + `@Published`，本地与 CI 都能编译。
@MainActor
final class ManualDraft: ObservableObject {
    @Published var name = ""
    @Published var latitude = ""
    @Published var longitude = ""
    @Published var note = ""
    @Published var kind: ObjectKind = .pole
}

struct ManualEntryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = ManualDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手动输入点位").font(.headline)

            Form {
                Picker("类型", selection: $draft.kind) {
                    ForEach(ObjectKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("点名（留空自动编号）", text: $draft.name)
                TextField("纬度（如 32.1301）", text: $draft.latitude)
                TextField("经度（如 114.0814）", text: $draft.longitude)
                TextField("备注", text: $draft.note)
            }
            .formStyle(.grouped)
            .frame(height: 210)

            Text("支持粘贴「32.1301, 114.0814」到纬度框，会自动拆分")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    guard let lat = Double(draft.latitude.trimmingCharacters(in: .whitespaces)),
                          let lon = Double(draft.longitude.trimmingCharacters(in: .whitespaces)) else { return }
                    state.addPointManually(
                        name: draft.name, latitude: lat, longitude: lon,
                        kind: draft.kind, note: draft.note
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(Double(draft.latitude) == nil || Double(draft.longitude) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: draft.latitude) { newValue in
            // 允许直接粘贴 "纬度, 经度"
            let parts = newValue.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            if parts.count == 2, Double(parts[0]) != nil, Double(parts[1]) != nil, draft.longitude.isEmpty {
                draft.latitude = parts[0]
                draft.longitude = parts[1]
            }
        }
        .onAppear { draft.kind = state.activeKind }
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
        HStack(spacing: 12) {
            Label("\(state.chain.pointCount) 点", systemImage: "mappin.and.ellipse")
            Text(String(format: "总长 %.1f m", state.chain.totalLength))
                .monospacedDigit()
            if let area = state.polygonArea {
                Text(String(format: "闭合面积 %.0f m²", area))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if state.project.applyGCJCorrection {
                Text("GCJ-02").font(.caption2).padding(.horizontal, 4)
                    .background(Color.orange.opacity(0.2)).cornerRadius(3)
            }

            Divider().frame(height: 14)

            if let point = state.selectedPoint {
                Text("\(point.name) \(point.coordinate.dms)")
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
