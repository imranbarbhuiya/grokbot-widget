import AppKit
import SwiftUI

struct DesktopSettings: Codable {
    var name: String
    var avatarPath: String
}

@MainActor final class DesktopRuntime {
    static let shared = DesktopRuntime()
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Grokbot Widget")
    var server: Process?
    var login: Process?
    var statusWindow: NSWindow?
    var bundled: Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        return FileManager.default.fileExists(atPath: resources.appendingPathComponent("scripts/desktop.mjs").path)
    }

    func configure() throws -> Bool {
        let file = support.appendingPathComponent("settings.json")
        let existing = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(DesktopSettings.self, from: $0) }
        let name = NSTextField(string: existing?.name ?? "")
        name.placeholderString = "Exact existing bot name"
        let avatar = NSTextField(string: existing?.avatarPath ?? "")
        avatar.placeholderString = "Optional custom image path"
        let fields = NSStackView(views: [NSTextField(labelWithString: "Bot name"), name, NSTextField(labelWithString: "Custom image (leave empty for the bot's cached avatar)"), avatar])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        name.widthAnchor.constraint(equalToConstant: 420).isActive = true
        avatar.widthAnchor.constraint(equalToConstant: 420).isActive = true
        let alert = NSAlert()
        alert.messageText = "Set up Grokbot Widget"
        alert.informativeText = "Use the exact name of a bot you already own. A misspelled name can create a new empty bot. Settings changes apply next time you open the widget."
        alert.accessoryView = fields
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Choose image…")
        NSApp.activate(ignoringOtherApps: true)
        while true {
            alert.window.initialFirstResponder = name
            let result = alert.runModal()
            if result == .alertSecondButtonReturn { return false }
            if result == .alertThirdButtonReturn {
                let picker = NSOpenPanel()
                picker.canChooseDirectories = false
                picker.allowsMultipleSelection = false
                if picker.runModal() == .OK, let url = picker.url { avatar.stringValue = url.path }
                continue
            }
            let bot = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if bot.isEmpty { alert.informativeText = "Enter your existing bot's exact name before saving."; continue }
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let settings = DesktopSettings(name: bot, avatarPath: avatar.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            try JSONEncoder().encode(settings).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        }
    }

    func prepare() async throws {
        guard bundled, let resources = Bundle.main.resourceURL else { return }
        if !FileManager.default.fileExists(atPath: support.appendingPathComponent("settings.json").path) {
            guard try configure() else { throw CancellationError() }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Grokbot Widget"
        window.contentView = NSHostingView(rootView: VStack(spacing: 16) {
            ProgressView()
            Text("Preparing your widget…").font(.headline)
            Text("First setup downloads the runtime. Complete browser sign-in if it opens.").multilineTextAlignment(.center).font(.caption)
        }.padding(24))
        window.center()
        window.makeKeyAndOrderFront(nil)
        statusWindow = window
        defer { window.close(); statusWindow = nil }
        let supportPath = support.path
        let resourcePath = resources.path
        let prepared = try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resourcePath).appendingPathComponent("node")
            process.arguments = [URL(fileURLWithPath: resourcePath).appendingPathComponent("scripts/desktop.mjs").path]
            process.environment = ProcessInfo.processInfo.environment.merging(["GROKBOT_SUPPORT_DIR": supportPath]) { _, value in value }
            let output = Pipe()
            process.standardOutput = output
            let logURL = URL(fileURLWithPath: supportPath).appendingPathComponent("runtime.log")
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            try log.seekToEnd()
            process.standardError = log
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw DesktopError.install }
            return try JSONDecoder().decode([String: String].self, from: data)
        }.value
        for (key, value) in prepared { setenv(key, value, 1) }
        guard let node = prepared["GROKBOT_NODE_PATH"], let project = prepared["GROKBOT_PROJECT_DIR"],
              let endpoint = prepared["GROKBOT_BDK_URL"], let url = URL(string: endpoint), let port = url.port else { throw DesktopError.install }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.currentDirectoryURL = URL(fileURLWithPath: project)
        process.arguments = ["node_modules/@cursor/bdk/dist/bin/agent-serve.js", "dev", "--host", "127.0.0.1", "--port", String(port), "--state-root", support.appendingPathComponent("state").path]
        let log = try FileHandle(forWritingTo: support.appendingPathComponent("runtime.log"))
        try log.seekToEnd()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        try log.close()
        server = process
        let health = url.deletingLastPathComponent()
        for _ in 0..<240 {
            guard process.isRunning else { throw DesktopError.server }
            if (try? await URLSession.shared.data(from: health)) != nil { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw DesktopError.server
    }

    func signIn() throws {
        guard login?.isRunning != true, let node = ProcessInfo.processInfo.environment["GROKBOT_NODE_PATH"],
              let project = ProcessInfo.processInfo.environment["GROKBOT_PROJECT_DIR"] else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.currentDirectoryURL = URL(fileURLWithPath: project)
        process.arguments = ["node_modules/@cursor/bdk/dist/bin/agent-serve.js", "login"]
        let log = try FileHandle(forWritingTo: support.appendingPathComponent("runtime.log"))
        try log.seekToEnd()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        try log.close()
        login = process
    }

    func stop() {
        if server?.isRunning == true { server?.terminate() }
        if login?.isRunning == true { login?.terminate() }
    }
}

enum DesktopError: LocalizedError {
    case install, server
    var errorDescription: String? {
        switch self {
        case .install: return "Could not prepare the runtime. Check your internet connection and runtime.log in Library/Application Support/Grokbot Widget, then reopen the app."
        case .server: return "The local server did not start. Complete browser sign-in if prompted, check runtime.log, then reopen the app."
        }
    }
}
