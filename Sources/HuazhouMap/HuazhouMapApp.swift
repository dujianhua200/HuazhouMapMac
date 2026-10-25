import SwiftUI

@main
struct HuazhouMapApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("滑洲云图 Mac") {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 1220, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建工程") { state.newProject() }
                    .keyboardShortcut("n")
                Button("打开工程…") { state.openProject() }
                    .keyboardShortcut("o")
                Divider()
                Button("从 CSV 导入…") { state.importCSV() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("从 KML 导入…") { state.importKML() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("保存") { state.saveProject() }
                    .keyboardShortcut("s")
                Button("另存为…") { state.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("手动输入点位…") { state.showManualEntry = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("导出 DXF…") { state.exportDXF() }
                    .keyboardShortcut("e")
                Button("导出点表 CSV…") { state.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("导出 KML…") { state.exportKML() }
                Button("导出 GPX…") { state.exportGPX() }
            }
        }
    }
}
