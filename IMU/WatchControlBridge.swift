//
//  WatchControlBridge.swift
//  IMU
//
//  Created by Codex on 2025-10-23.
//

import Foundation
import WatchConnectivity

/// 워치에서 전달될 수 있는 명령 집합
enum WatchCommand: String, Codable {
    case startCollection = "start"
    case resetSession = "reset"
    case toggleDebug = "toggle_debug"
    case toggleDummy = "toggle_dummy"
    case requestState = "request_state"

    init?(payload: [String: Any]) {
        guard
            let raw = payload["command"] as? String,
            let command = WatchCommand(rawValue: raw)
        else { return nil }
        self = command
    }

    var payload: [String: Any] {
        ["command": rawValue]
    }
}

/// 버튼 모양/색을 워치와 동기화하기 위한 표현
struct WatchButtonAppearance: Codable {
    enum TintToken: String, Codable {
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

    init(
        identifier: String,
        title: String,
        systemImage: String,
        tintToken: TintToken,
        command: WatchCommand,
        isEnabled: Bool = true,
        isHighlighted: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.systemImage = systemImage
        self.tintToken = tintToken
        self.command = command
        self.isEnabled = isEnabled
        self.isHighlighted = isHighlighted
    }
}

extension WatchButtonAppearance {
    var payload: [String: Any] {
        [
            "identifier": identifier,
            "title": title,
            "systemImage": systemImage,
            "tintToken": tintToken.rawValue,
            "command": command.rawValue,
            "isEnabled": isEnabled,
            "isHighlighted": isHighlighted
        ]
    }
}

/// 워치 UI가 필요로 하는 전체 상태 패킷
struct WatchAppState: Codable {
    var lastUpdated: TimeInterval
    var statusMessage: String?
    var connectionMessage: String?
    var buttonAppearances: [WatchButtonAppearance]

    init(
        statusMessage: String?,
        connectionMessage: String?,
        buttonAppearances: [WatchButtonAppearance],
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.statusMessage = statusMessage
        self.connectionMessage = connectionMessage
        self.buttonAppearances = buttonAppearances
        self.lastUpdated = timestamp
    }

    var payload: [String: Any] {
        var output: [String: Any] = [
            "lastUpdated": lastUpdated,
            "buttonAppearances": buttonAppearances.map { $0.payload }
        ]
        if let statusMessage {
            output["statusMessage"] = statusMessage
        }
        if let connectionMessage {
            output["connectionMessage"] = connectionMessage
        }
        return output
    }
}

protocol WatchControlBridgeDelegate: AnyObject {
    func watchControlBridge(_ bridge: WatchControlBridge, didReceive command: WatchCommand)
    func watchControlBridgeCurrentState(_ bridge: WatchControlBridge) -> WatchAppState
}

/// 워치와 메시지를 교환해 버튼 명령과 상태를 동기화하는 브리지
final class WatchControlBridge: NSObject {
    weak var delegate: WatchControlBridgeDelegate?

    private let session: WCSession?
    private let queue = DispatchQueue(label: "com.codex.telemetry.watchbridge")

    override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }
        super.init()
        configureSession()
    }

    private func configureSession() {
        guard let session else { return }
        let activateBlock = {
            session.delegate = self
            session.activate()
        }

        if Thread.isMainThread {
            activateBlock()
        } else {
            DispatchQueue.main.async(execute: activateBlock)
        }
    }

    /// 워치로 최신 버튼/상태 정보를 전송
    func pushState(_ state: WatchAppState) {
        guard let session else { return }
        let payload = state.payload
        queue.async {
            do {
                try session.updateApplicationContext(payload)
            } catch {
                // updateApplicationContext는 한 번에 하나만 유지되므로 실패 시 UserInfo 큐에 넣는다.
                session.transferUserInfo(payload)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchControlBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil else { return }
        if activationState == .activated {
            let state = delegate?.watchControlBridgeCurrentState(self)
            if let state {
                pushState(state)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchCommand(payload: message) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if command == .requestState, let state = self.delegate?.watchControlBridgeCurrentState(self) {
                self.pushState(state)
            } else {
                self.delegate?.watchControlBridge(self, didReceive: command)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = WatchCommand(payload: message) else {
            replyHandler([:])
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if command == .requestState, let state = self.delegate?.watchControlBridgeCurrentState(self) {
                replyHandler(state.payload)
            } else {
                self.delegate?.watchControlBridge(self, didReceive: command)
                if let state = self.delegate?.watchControlBridgeCurrentState(self) {
                    replyHandler(state.payload)
                } else {
                    replyHandler([:])
                }
            }
        }
    }
}
