import SwiftUI
import AppKit
import HuazhouAppCore

/// 处理 Finder / `open -a` 传来的工程文件打开事件
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var state: AppState?
    private var pending: [URL] = []

    func attach(_ state: AppState) {
        self.state = state
        flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--self-test") else { return }
        let ok = AppSelfTest.runAndReport { line in
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
        exit(ok ? 0 : 1)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pending.append(contentsOf: urls)
        flush()
    }

    private func flush() {
        guard let state else { return }
        guard let url = pending.first(where: { $0.pathExtension.lowercased() == "hzmap" }) else {
            pending = []
            return
        }
        pending = []
        do {
            try state.load(from: url)
        } catch {
            state.message = "打开失败：\(error.localizedDescription)"
        }
    }
}

@main
struct HuazhouMapApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("滑洲云图 Mac") {
            ContentView()
                .environmentObject(state)
                .task {
                    appDelegate.attach(state)
                    state.loadStartupProjectFromCommandLine()
                }
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
