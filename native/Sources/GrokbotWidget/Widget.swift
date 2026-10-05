import AppKit
import SwiftUI

struct ToolResponse: Decodable {
    let ok: Bool
    let isError: Bool?
    let result: Reply?
    struct Reply: Decodable {
        let status: String?
        let reply: String?
        let created: Bool?
    }
}

struct Message: Identifiable {
    let id = UUID()
    let text: String
    let fromUser: Bool
}

@MainActor final class Chat: ObservableObject {
    @Published var messages: [Message] = []
    @Published var busy = false
    @Published var error: String?
    let name = ProcessInfo.processInfo.environment["GROKBOT_AGENT_NAME"] ?? "Bot"

    func send(_ text: String) {
        guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(Message(text: text, fromUser: true))
        busy = true
        error = nil
        Task {
            do {
                var response = try await Self.call("grokbot__ask", message: text)
                for _ in 0..<15 {
                    if response.created == true { throw WidgetError.newBot }
                    if let reply = response.reply, !reply.isEmpty {
                        messages.append(Message(text: reply, fromUser: false))
                    }
                    if response.status == "finished" { busy = false; return }
                    if response.status != "running" { throw WidgetError.badResponse }
                    response = try await Self.call("grokbot__check", message: nil)
                }
                error = "Still working. Open Grokbot to see the reply."
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    nonisolated static func call(_ tool: String, message: String?) async throws -> ToolResponse.Reply {
        try await Task.detached {
            let env = ProcessInfo.processInfo.environment
            guard let project = env["GROKBOT_PROJECT_DIR"], let node = env["GROKBOT_NODE_PATH"] else {
                throw WidgetError.configuration
            }
            var input: [String: Any] = ["wait_seconds": 20]
            if let message { input["message"] = message }
            let payload = try JSONSerialization.data(withJSONObject: input)
            guard let json = String(data: payload, encoding: .utf8) else { throw WidgetError.badResponse }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: node)
            process.currentDirectoryURL = URL(fileURLWithPath: project)
            process.arguments = ["--env-file-if-exists=.env", "node_modules/@cursor/bdk/dist/bin/agent-serve.js", "call", tool, "--url", env["GROKBOT_BDK_URL"] ?? "http://127.0.0.1:4317/grokbot-widget", "--input", json]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw WidgetError.connection }
            let decoded = try JSONDecoder().decode(ToolResponse.self, from: data)
            guard decoded.ok, decoded.isError != true, let reply = decoded.result else { throw WidgetError.badResponse }
            return reply
        }.value
    }
}

enum WidgetError: LocalizedError {
    case configuration, connection, badResponse, newBot
    var errorDescription: String? {
        switch self {
        case .configuration: return "Launch with npm run widget from the project folder."
        case .connection: return "Couldn’t reach your bot. Check BDK sign-in and the local server."
        case .badResponse: return "The bot didn’t return a completed reply. Open Grokbot to check."
        case .newBot: return "BDK created a new bot. Check your account and configured bot name before sending again."
        }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct WindowDragSurface: NSViewRepresentable {
    let onClick: () -> Void

    final class DragView: NSView {
        var onClick: () -> Void = {}
        private var start = NSPoint.zero
        private var origin = NSPoint.zero
        private var dragging = false

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = window.convertPoint(toScreen: event.locationInWindow)
            origin = window.frame.origin
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let dx = point.x - start.x
            let dy = point.y - start.y
            if hypot(dx, dy) >= 4 { dragging = true }
            if dragging { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
        }

        override func mouseUp(with event: NSEvent) {
            if !dragging { onClick() }
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.onClick = onClick }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: FloatingPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 230), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: WidgetView { expanded in
            let size = expanded ? NSSize(width: 380, height: 640) : NSSize(width: 190, height: 230)
            let right = panel.frame.maxX
            let bottom = panel.frame.minY
            var frame = NSRect(x: right - size.width, y: bottom, width: size.width, height: size.height)
            if let screen = panel.screen {
                let bounds = screen.visibleFrame
                frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size.width)
                frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
            }
            panel.setFrame(frame, display: true)
            if expanded { panel.makeKey(); NSApp.activate(ignoringOtherApps: true) }
        })
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 210, y: screen.visibleFrame.minY + 30))
        }
        if let saved = UserDefaults.standard.string(forKey: "widgetFrame") {
            let frame = NSRectFromString(saved)
            let origin = NSRect(origin: frame.origin, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(origin) }) {
                panel.setFrameOrigin(origin.origin)
            }
        }
        panel.delegate = self
        self.panel = panel
        panel.orderFrontRegardless()
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit widget", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    func windowDidMove(_ notification: Notification) {
        if let panel { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "widgetFrame") }
    }
}

struct WidgetView: View {
    @StateObject private var chat = Chat()
    @State private var expanded = false
    @State private var draft = ""
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let resize: (Bool) -> Void
    let avatar = ProcessInfo.processInfo.environment["GROKBOT_AVATAR_PATH"].flatMap { NSImage(contentsOfFile: $0) }

    func openBot() {
        let env = ProcessInfo.processInfo.environment
        if let link = env["GROKBOT_OPEN_URL"], let url = URL(string: link), url.scheme == "grokbot" {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: env["GROKBOT_APP_PATH"] ?? "/Applications/Grok Bot.app"), configuration: .init())
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if expanded {
                VStack(spacing: 12) {
                    HStack {
                        Text(chat.name).font(.headline)
                        Spacer()
                        Text(chat.busy ? "Thinking…" : "Ready").font(.caption).foregroundStyle(.secondary)
                        Button { expanded = false; resize(false) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Close chat")
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                if chat.messages.isEmpty {
                                    Text("What’s on your mind?").foregroundStyle(.secondary).padding(.top, 32)
                                }
                                ForEach(chat.messages) { message in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.fromUser ? "You" : chat.name).font(.caption).foregroundStyle(.secondary)
                                        Text(message.text).textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, alignment: .leading).id(message.id)
                                }
                                if chat.busy {
                                    HStack(spacing: 8) {
                                        if reduceMotion {
                                            Image(systemName: "hourglass")
                                        } else {
                                            ProgressView().controlSize(.small)
                                        }
                                        Text("Waiting for \(chat.name)…").font(.callout).foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .id("pending")
                                }
                            }.padding(.vertical, 8)
                        }
                        .onChange(of: chat.busy) { _, busy in
                            if busy { proxy.scrollTo("pending", anchor: .bottom) }
                        }
                        .onChange(of: chat.messages.count) { _, _ in
                            if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                    if let error = chat.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    HStack(alignment: .bottom) {
                        TextField("Message \(chat.name)", text: $draft, axis: .vertical)
                            .lineLimit(1...4).textFieldStyle(.plain)
                        Button {
                            chat.send(draft)
                            draft = ""
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(chat.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.plain).accessibilityLabel("Send message")
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !chat.busy || reduceMotion)) { context in
                    let wave = chat.busy && !reduceMotion ? sin(context.date.timeIntervalSinceReferenceDate * .pi * 1.6) : 0
                    Group {
                    if let avatar { Image(nsImage: avatar).resizable().scaledToFit() }
                    else {
                        ZStack {
                            Circle().fill(.blue)
                            HStack(spacing: 15) {
                                Capsule().fill(.black).frame(width: 12, height: 27)
                                Capsule().fill(.black).frame(width: 12, height: 27)
                            }.rotationEffect(.degrees(-20))
                        }.padding(20)
                    }
                }.frame(width: 155, height: 155)
                    .scaleEffect(hovering && !reduceMotion ? 1.05 : 1)
                    .rotationEffect(.degrees(wave * 3))
                    .offset(y: wave * 3)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: hovering)
                }
                WindowDragSurface { expanded.toggle(); resize(expanded) }
            }.frame(width: 155, height: 155)
                .onHover { hovering = $0 }
                .help("Drag to move; click to chat")
                .accessibilityLabel("Toggle \(chat.name) chat")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { expanded.toggle(); resize(expanded) }
            HStack(spacing: 18) {
                Button { expanded.toggle(); resize(expanded) } label: { Image(systemName: "square.and.pencil") }
                    .help("Chat with \(chat.name)")
                Button(action: openBot) { Image(systemName: "arrow.up.forward.app") }.help("Open Grokbot")
                Button(action: openBot) { Image(systemName: "waveform") }.help("Open Grokbot, then start voice chat there")
            }.buttonStyle(.plain).font(.system(size: 20)).padding(.horizontal, 18).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }.padding(12)
            .contextMenu {
                Button("Open Grokbot", action: openBot)
                Button("Quit widget") { NSApp.terminate(nil) }
            }
    }
}

@main enum WidgetApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
