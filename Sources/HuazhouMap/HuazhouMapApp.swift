import SwiftUI

@main
struct HuazhouMapApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("滑洲云图 Mac") {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建工程") { state.newProject() }
                    .keyboardShortcut("n")
                Button("打开工程…") { state.openProject() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .saveItem) {
                Button("保存") { state.saveProject() }
                    .keyboardShortcut("s")
                Button("另存为…") { state.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("导出 DXF…") { state.exportDXF() }
                    .keyboardShortcut("e")
                Button("导出点表 CSV…") { state.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
