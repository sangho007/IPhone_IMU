//
//  TelemetryViewModel.swift
//  IMU
//
//  Created by Codex on 2025-10-23.
//

import ARKit
import CoreMotion
import Foundation
import Network
import simd

/// ARKit, CoreMotion, TCP 전송을 묶어 DTO를 실시간 구성·전송하는 뷰모델
final class TelemetryViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var telemetry: TelemetryDTO
    @Published var statusMessage: String?
    @Published var connectionStatusMessage: String?
    @Published private(set) var isCollecting: Bool = false
    @Published private(set) var isConnecting: Bool = false
    @Published private(set) var isDebugMode: Bool = false

    private let session = ARSession()
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    private var lastFrameTimestamp: TimeInterval?
    private var lastWorldPosition: SIMD3<Float>?
    private var lastHeaderUpdate: TimeInterval?
    private var sequence: Int = 0
    private var originID: Int = 0
    private var currentNonce: String = TelemetryViewModel.makeNonce()
    private var worldVelocity: SIMD3<Float> = .zero

    private var connection: NWConnection?
    private var connectionAttempts: Int = 0

    private let networkQueue = DispatchQueue(label: "com.codex.telemetry.network")
    private let sendQueue = DispatchQueue(label: "com.codex.telemetry.send")
    private var sendTimer: DispatchSourceTimer?

    private let config = ConnectionConfig.default

    override init() {
        telemetry = TelemetryDTO.sample
        super.init()
        motionQueue.name = "com.codex.telemetry.motion"
        session.delegate = self
    }

    deinit {
        stop()
    }

    /// 센서 수집 + TCP 연결을 순차적으로 시작
    func start() {
        if isDebugMode {
            guard !isCollecting else { return }
            startCollectionFlow(reason: "startup", shouldSend: false)
            return
        }

        guard !isCollecting else { return }
        guard !isConnecting else { return }
        isConnecting = true
        connectionStatusMessage = "수신자와 연결 중..."
        networkQueue.async { [weak self] in
            guard let self else { return }
            self.connectionAttempts = 0
            self.attemptConnection()
        }
    }

    /// 모든 센서 업데이트 및 연결을 중지
    func stop(message: String? = "센서 수집이 중지되었습니다.") {
        stopCollection(message: message)
        isConnecting = false
        networkQueue.async { [weak self] in
            guard let self else { return }
            self.connectionAttempts = 0
            self.tearDownConnection()
        }

        connectionStatusMessage = "연결이 종료되었습니다."
    }

    /// 세션 파라미터와 누적 상태를 초기화
    func reset() {
        guard isCollecting else { return }
        let shouldSend = !isDebugMode
        startCollectionFlow(reason: "manual", shouldSend: shouldSend)
        statusMessage = "세션이 리셋되었습니다."
    }

    // MARK: - 연결 관리

    private func attemptConnection() {
        guard let port = config.port else {
            DispatchQueue.main.async { [weak self] in
                self?.isConnecting = false
                self?.connectionStatusMessage = "잘못된 포트 설정입니다."
            }
            return
        }

        connectionAttempts += 1

        tearDownConnection()

        let connection = NWConnection(host: config.host, port: port, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state)
        }
        self.connection = connection
        connection.start(queue: networkQueue)

        let attempts = connectionAttempts
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let attemptText = "\(attempts)/\(self.config.maxConnectionAttempts)"
            self.connectionStatusMessage = "수신자와 연결 중... (\(attemptText))"
        }
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionReady()
        case .waiting(let error):
            connectionFailed(with: error)
        case .failed(let error):
            connectionFailed(with: error)
        case .cancelled:
            break
        default:
            break
        }
    }

    private func connectionReady() {
        connectionAttempts = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnecting = false
            self.statusMessage = "연결 성공. 센서 수집 준비 중..."
            self.startCollectionFlow(reason: "startup", shouldSend: true)
        }
    }

    private func connectionFailed(with error: NWError) {
        tearDownConnection()
        stopCollection()
        scheduleRetry(after: error)
    }

    private func scheduleRetry(after error: NWError?) {
        let attempts = connectionAttempts

        if attempts >= config.maxConnectionAttempts {
            finalizeConnectionFailure(lastError: error)
            return
        }

        let message = connectionErrorMessage(for: error)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let attemptText = "\(attempts)/\(self.config.maxConnectionAttempts)"
            self.connectionStatusMessage = "\(message) 재시도 예정 (\(attemptText))"
        }

        networkQueue.asyncAfter(deadline: .now() + config.retryDelay) { [weak self] in
            guard let self else { return }
            self.attemptConnection()
        }
    }

    private func finalizeConnectionFailure(lastError: NWError?) {
        tearDownConnection()
        let maxAttempts = config.maxConnectionAttempts
        let finalMessage: String
        if let error = lastError {
            finalMessage = "수신자 연결 실패: \(error.shortDescription) - 최대 \(maxAttempts)회 재시도 후 중단되었습니다."
        } else {
            finalMessage = "수신자 연결 실패 - 최대 \(maxAttempts)회 재시도 후 중단되었습니다."
        }

        stopCollection(message: finalMessage)

        DispatchQueue.main.async { [weak self] in
            self?.isConnecting = false
            self?.connectionStatusMessage = finalMessage
        }
    }

    private func tearDownConnection() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: - 센서 수집 및 전송

    private func startCollectionFlow(reason: String, shouldSend: Bool) {
        assert(Thread.isMainThread)

        guard configureSession(reason: reason) else { return }

        startMotionUpdatesIfNeeded()
        if shouldSend {
            startSendLoop()
        } else {
            stopSendLoop()
        }

        isCollecting = true
        statusMessage = shouldSend
            ? "센서 수집 및 전송 중 (\(Int(config.sendFrequency))Hz)"
            : "디버그 모드 - 센서만 수집 중"
        connectionStatusMessage = shouldSend ? "연결 유지 중" : "디버그 모드: 연결 없음"
    }

    private func stopCollection(message: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.session.pause()
            self.motionManager.stopDeviceMotionUpdates()
            self.stopSendLoop()
            self.isCollecting = false
            if let message {
                self.statusMessage = message
            }
        }
    }

    private func startSendLoop() {
        stopSendLoop()
        let interval = 1.0 / config.sendFrequency
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sendCurrentTelemetry()
        }
        timer.resume()
        sendTimer = timer
    }

    private func stopSendLoop() {
        sendTimer?.cancel()
        sendTimer = nil
    }

    private func sendCurrentTelemetry() {
        guard let connection else { return }
        let collecting = DispatchQueue.main.sync { self.isCollecting }
        guard collecting else { return }

        let dto = DispatchQueue.main.sync { self.telemetry }
        let payload = TelemetryProtobufEncoder.encode(dto)

        guard payload.count <= Int(UInt32.max) else { return }

        var frame = Data(capacity: payload.count + MemoryLayout<UInt32>.size)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)

        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.handleSendFailure(error)
        })
    }

    private func handleSendFailure(_ error: NWError) {
        networkQueue.async { [weak self] in
            guard let self else { return }
            self.tearDownConnection()
            self.connectionAttempts = 0
            self.stopCollection()
            self.scheduleRetry(after: error)
        }
    }

    // MARK: - AR / Motion 처리

    /// ARWorldTracking을 재시작하고 DTO의 기본값 갱신
    @discardableResult
    private func configureSession(reason: String) -> Bool {
        guard ARWorldTrackingConfiguration.isSupported else {
            updateTelemetry { dto in
                dto.status.tracking = "LOST"
                dto.status.statusReason = "unsupported"
                dto.status.trackingConfidence = 0.0
            }
            statusMessage = "이 기기는 ARKit 월드 트래킹을 지원하지 않습니다."
            return false
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .automatic

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        sequence = 0
        lastFrameTimestamp = nil
        lastWorldPosition = nil
        lastHeaderUpdate = nil
        worldVelocity = .zero
        originID += 1
        currentNonce = TelemetryViewModel.makeNonce()

        updateTelemetry { dto in
            dto.header.sessionID = TelemetryViewModel.makeSessionID()
            dto.header.seq = 0
            dto.poseWorldPhone.valid = false
            dto.velocity.valid = false
            dto.status.flags = ["NO_JUMP", "NO_RELOCALIZE"]
            dto.originReset.originID = self.originID
            dto.originReset.applyAtStampNS = 0
            dto.originReset.nonce = self.currentNonce
            dto.originReset.reason = reason
        }

        return true
    }

    /// CoreMotion으로부터 가속도/자이로를 받아 DTO에 저장
    private func startMotionUpdatesIfNeeded() {
        motionManager.stopDeviceMotionUpdates()

        guard motionManager.isDeviceMotionAvailable else {
            statusMessage = "기기 모션 센서를 사용할 수 없습니다."
            updateTelemetry { dto in
                dto.acceleration.valid = false
                dto.gyro.valid = false
            }
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.statusMessage = "모션 업데이트 오류: \(error.localizedDescription)"
                }
                return
            }

            guard let motion else { return }

            let userAcceleration = motion.userAcceleration
            let rotation = motion.attitude.rotationMatrix

            let worldX = rotation.m11 * userAcceleration.x + rotation.m12 * userAcceleration.y + rotation.m13 * userAcceleration.z
            let worldY = rotation.m21 * userAcceleration.x + rotation.m22 * userAcceleration.y + rotation.m23 * userAcceleration.z
            let worldZ = rotation.m31 * userAcceleration.x + rotation.m32 * userAcceleration.y + rotation.m33 * userAcceleration.z

            let rotationRate = motion.rotationRate

            self.updateTelemetry { dto in
                dto.acceleration.bodyNoGravity = TelemetryDTO.Vector3(x: userAcceleration.x, y: userAcceleration.y, z: userAcceleration.z)
                dto.acceleration.world = TelemetryDTO.Vector3(x: worldX, y: worldY, z: worldZ)
                dto.acceleration.valid = true
                dto.acceleration.source = "CoreMotion"
                dto.gyro.body = TelemetryDTO.Vector3(x: rotationRate.x, y: rotationRate.y, z: rotationRate.z)
                dto.gyro.bias = TelemetryDTO.Vector3(x: 0, y: 0, z: 0)
                dto.gyro.valid = true
                dto.gyro.source = "CoreMotion"
            }

            self.updateHeaderTiming()
        }
    }

    /// ARKit 프레임이 새로 들어올 때마다 위치/자세/속도 갱신
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let orientation = simd_quaternion(transform)

        var velocity = worldVelocity
        if let lastPosition = lastWorldPosition, let lastTimestamp = lastFrameTimestamp {
            let deltaPosition = position - lastPosition
            let deltaTime = max(Float(frame.timestamp - lastTimestamp), 1e-5)
            velocity = deltaPosition / deltaTime
            worldVelocity = velocity
        }

        lastWorldPosition = position
        lastFrameTimestamp = frame.timestamp

        let trackingInfo = tracking(from: frame.camera.trackingState)
        let featureCount = frame.rawFeaturePoints?.points.count ?? 0

        updateTelemetry { dto in
            dto.status.tracking = trackingInfo.tracking
            dto.status.statusReason = trackingInfo.reason
            dto.status.trackingConfidence = trackingInfo.confidence
            dto.status.numFeatures = featureCount
            dto.poseWorldPhone.position = TelemetryDTO.Vector3(x: Double(position.x), y: Double(position.y), z: Double(position.z))
            dto.poseWorldPhone.orientationQuat = TelemetryDTO.Quaternion(
                x: Double(orientation.vector.x),
                y: Double(orientation.vector.y),
                z: Double(orientation.vector.z),
                w: Double(orientation.vector.w)
            )
            dto.poseWorldPhone.valid = true
            dto.velocity.world = TelemetryDTO.Vector3(x: Double(velocity.x), y: Double(velocity.y), z: Double(velocity.z))
            dto.velocity.valid = true
            dto.velocity.source = "ARKit_diff"
        }

        updateHeaderTiming()
    }

    /// ARKit이 제공하는 TrackingState를 DTO 표현으로 변환
    private func tracking(from state: ARCamera.TrackingState) -> (tracking: String, reason: String, confidence: Double) {
        switch state {
        case .normal:
            return ("OK", "none", 1.0)
        case .notAvailable:
            return ("LOST", "not_available", 0.0)
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return ("LIMITED", "motion_blur", 0.4)
            case .insufficientFeatures:
                return ("LIMITED", "low_texture", 0.5)
            case .initializing:
                return ("LIMITED", "startup", 0.3)
            case .relocalizing:
                return ("LIMITED", "relocalize", 0.6)
            @unknown default:
                return ("LIMITED", "unknown", 0.5)
            }
        }
    }

    /// 헤더의 타임스탬프/주기/시퀀스 업데이트
    private func updateHeaderTiming() {
        let now = Date().timeIntervalSince1970
        let delta = now - (lastHeaderUpdate ?? now)
        lastHeaderUpdate = now

        sequence += 1
        let stamp = Int(now * 1_000_000_000)
        let dt = max(delta, 0) * 1_000_000_000

        updateTelemetry { dto in
            dto.header.stampNS = stamp
            dto.header.dtNS = Int(dt)
            dto.header.seq = self.sequence
        }
    }

    /// 메인 스레드에서 DTO를 안전하게 변경
    private func updateTelemetry(_ update: @escaping (inout TelemetryDTO) -> Void) {
        DispatchQueue.main.async {
            var dto = self.telemetry
            update(&dto)
            self.telemetry = dto
        }
    }

    /// 디버그 모드를 토글 (통신 없이 센서만 수집)
    func toggleDebugMode() {
        let targetState = !isDebugMode
        stop(message: nil)
        isDebugMode = targetState
        statusMessage = targetState
            ? "디버그 모드 활성화: 통신 없이 센서만 수집합니다."
            : "디버그 모드 비활성화"
        connectionStatusMessage = targetState
            ? "디버그 모드: 연결 시도 안 함"
            : "디버그 모드 비활성화됨"
    }
}

// MARK: - 유틸

private extension TelemetryViewModel {
    static func makeSessionID() -> String {
        let formatter = sessionFormatter
        return formatter.string(from: Date())
    }

    static func makeNonce() -> String {
        let value = UUID().uuidString.prefix(8)
        return "\(value)..."
    }

    static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    func connectionErrorMessage(for error: NWError?) -> String {
        if let error {
            return "연결 오류: \(error.shortDescription)"
        } else {
            return "연결이 끊겼습니다."
        }
    }
}

private extension TelemetryViewModel {
    struct ConnectionConfig {
        let host: NWEndpoint.Host
        let port: NWEndpoint.Port?
        let maxConnectionAttempts: Int
        let retryDelay: TimeInterval
        let sendFrequency: Double

        static let `default` = ConnectionConfig(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: 4820),
            maxConnectionAttempts: 5,
            retryDelay: 1.5,
            sendFrequency: 30
        )
    }
}

private extension NWError {
    var shortDescription: String {
        switch self {
        case .posix(let code):
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(code.rawValue), userInfo: nil)
            let message = error.localizedFailureReason ?? error.localizedDescription
            return "POSIX(\(code.rawValue)): \(message)"
        case .dns(let code):
            return "DNS(\(code))"
        case .tls(let code):
            return "TLS(\(code))"
        @unknown default:
            return localizedDescription
        }
    }
}

#if DEBUG
extension TelemetryViewModel {
    static func preview() -> TelemetryViewModel {
        let viewModel = TelemetryViewModel()
        viewModel.telemetry = .sample
        return viewModel
    }
}
#endif
