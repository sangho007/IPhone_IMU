//
//  ContentView.swift
//  IMU_Remote Watch App
//
//  Created by 이상호 on 11/11/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var viewModel = RemoteControlViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                StatusCard(
                    statusMessage: viewModel.statusMessage,
                    connectionMessage: viewModel.connectionMessage,
                    reachabilityDescription: viewModel.reachabilityDescription,
                    lastUpdated: viewModel.lastUpdated
                )

                if viewModel.buttons.isEmpty {
                    ProgressView("아이폰 상태 수신 대기 중…")
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.buttons) { button in
                        ControlButtonView(button: button) {
                            viewModel.performAction(for: button)
                        }
                        .disabled(!button.isEnabled)
                        .opacity(button.isEnabled ? 1 : 0.4)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .onAppear {
            viewModel.requestLatestState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            viewModel.requestLatestState()
        }
    }
}

// MARK: - Status Card

private struct StatusCard: View {
    let statusMessage: String?
    let connectionMessage: String?
    let reachabilityDescription: String
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let statusMessage {
                Label(statusMessage, systemImage: "info.circle")
                    .font(.footnote)
            } else {
                Label("상태 메시지 없음", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            if let connectionMessage {
                Text(connectionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(reachabilityDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let lastUpdated {
                Text("업데이트: \(lastUpdated.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Button View

private struct ControlButtonView: View {
    let button: WatchButtonAppearance
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: button.systemImage)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.title)
                        .font(.body)
                    if button.isHighlighted {
                        Text("활성화됨")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(
            ControlButtonStyle(
                isHighlighted: button.isHighlighted,
                tintColor: button.tintToken.color
            )
        )
    }
}

private struct ControlButtonStyle: ButtonStyle {
    var isHighlighted: Bool
    var tintColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(isHighlighted ? Color.black : tintColor)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isHighlighted
                            ? tintColor.opacity(configuration.isPressed ? 0.6 : 0.9)
                            : tintColor.opacity(0.15)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isHighlighted ? Color.clear : tintColor.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

// MARK: - View Model

final class RemoteControlViewModel: NSObject, ObservableObject {
    @Published private(set) var statusMessage: String?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var buttons: [WatchButtonAppearance] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var reachabilityDescription: String = "아이폰 연결 대기 중"

    private var session: WCSession?
    private var pendingCommands: [PendingCommand] = []

    override init() {
        super.init()
        configureSession()
    }

    func performAction(for button: WatchButtonAppearance) {
        sendCommand(button.command)
    }

    func requestLatestState() {
        sendCommand(.requestState)
    }

    private func configureSession() {
        guard WCSession.isSupported() else {
            reachabilityDescription = "이 워치에서는 WatchConnectivity를 사용할 수 없습니다."
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    private func sendCommand(_ command: WatchCommand) {
        guard let session else { return }
        guard session.activationState == .activated else {
            pendingCommands.append(.init(command: command))
            if session.activationState == .notActivated {
                session.activate()
            }
            return
        }

        performSend(command: command, session: session)
    }

    private func performSend(command: WatchCommand, session: WCSession) {
        let payload = command.payload

        if session.isReachable {
            session.sendMessage(payload) { [weak self] response in
                self?.applyState(response)
            } errorHandler: { [weak self] error in
                self?.setConnectionMessage("아이폰 응답 없음: \(error.localizedDescription)")
            }
            return
        }

        session.transferUserInfo(payload)

        DispatchQueue.main.async { [weak self] in
            self?.reachabilityDescription = "아이폰 연결 대기 중"
        }
    }

    private func applyState(_ payload: [String: Any]) {
        guard let state = WatchAppState(payload: payload) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusMessage = state.statusMessage
            self.connectionMessage = state.connectionMessage
            self.buttons = state.buttonAppearances
            self.lastUpdated = state.lastUpdated
            self.reachabilityDescription = "아이폰과 동기화됨"
        }
    }

    private func setConnectionMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionMessage = message
        }
    }
}

// MARK: - WCSessionDelegate

extension RemoteControlViewModel: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            setConnectionMessage("세션 오류: \(error.localizedDescription)")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reachabilityDescription = activationState == .activated
                ? (session.isReachable ? "아이폰과 연결됨" : "아이폰 연결 대기 중")
                : "세션 비활성화됨"
        }

        flushPendingCommands(using: session)
        requestLatestState()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reachabilityDescription = isReachable ? "아이폰과 연결됨" : "아이폰 연결 대기 중"
            if isReachable {
                self.requestLatestState()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyState(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        applyState(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyState(message)
    }
}

// MARK: - Pending Command

private extension RemoteControlViewModel {
    struct PendingCommand {
        let command: WatchCommand
    }

    func flushPendingCommands(using session: WCSession) {
        guard session.activationState == .activated else { return }
        let commands = pendingCommands
        pendingCommands.removeAll()
        commands.forEach { performSend(command: $0.command, session: session) }
    }
}

// MARK: - Payload Models

enum WatchCommand: String {
    case startCollection = "start"
    case resetSession = "reset"
    case toggleDebug = "toggle_debug"
    case toggleDummy = "toggle_dummy"
    case requestState = "request_state"

    var payload: [String: Any] {
        ["command": rawValue]
    }
}

struct WatchButtonAppearance: Identifiable {
    enum TintToken: String {
        case primary
        case secondary
        case orange
        case pink
        case disabled
    }

    var identifier: String
    var title: String
    var systemImage: String
    var tintToken: TintToken
    var command: WatchCommand
    var isEnabled: Bool
    var isHighlighted: Bool

    var id: String { identifier }

    init?(payload: [String: Any]) {
        guard
            let identifier = payload["identifier"] as? String,
            let title = payload["title"] as? String,
            let systemImage = payload["systemImage"] as? String,
            let tintRaw = payload["tintToken"] as? String,
            let tintToken = TintToken(rawValue: tintRaw),
            let commandRaw = payload["command"] as? String,
            let command = WatchCommand(rawValue: commandRaw),
            let isEnabled = payload["isEnabled"] as? Bool,
            let isHighlighted = payload["isHighlighted"] as? Bool
        else { return nil }

        self.identifier = identifier
        self.title = title
        self.systemImage = systemImage
        self.tintToken = tintToken
        self.command = command
        self.isEnabled = isEnabled
        self.isHighlighted = isHighlighted
    }
}

struct WatchAppState {
    var statusMessage: String?
    var connectionMessage: String?
    var buttonAppearances: [WatchButtonAppearance]
    var lastUpdated: Date?

    init?(payload: [String: Any]) {
        guard let buttonPayloads = payload["buttonAppearances"] as? [[String: Any]] else { return nil }
        let buttons = buttonPayloads.compactMap { WatchButtonAppearance(payload: $0) }

        guard !buttons.isEmpty else { return nil }

        statusMessage = payload["statusMessage"] as? String
        connectionMessage = payload["connectionMessage"] as? String
        buttonAppearances = buttons
        if let timestamp = payload["lastUpdated"] as? TimeInterval {
            lastUpdated = Date(timeIntervalSince1970: timestamp)
        }
    }
}

private extension WatchButtonAppearance.TintToken {
    var color: Color {
        switch self {
        case .primary:
            return .accentColor
        case .secondary:
            return .gray
        case .orange:
            return .orange
        case .pink:
            return .pink
        case .disabled:
            return .gray.opacity(0.6)
        }
    }
}
