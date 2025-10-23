//
//  ContentView.swift
//  IMU
//
//  Created by Codex on 2025-10-23.
//

import SwiftUI
import UIKit

/// DTO 값을 섹션별로 보여주는 메인 화면
struct ContentView: View {
    @StateObject private var viewModel: TelemetryViewModel

    init(viewModel: TelemetryViewModel = TelemetryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        let dto = viewModel.telemetry

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let statusMessage = viewModel.statusMessage {
                        /// 현재 수집 상태를 간단히 표시
                        section(title: "Status Message") {
                            Text(statusMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section(title: "Schema") {
                        keyValue("schema_version", dto.schemaVersion)
                    }

                    if let connectionMessage = viewModel.connectionStatusMessage {
                        section(title: "Connection Status") {
                            Text(connectionMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section(title: "Header") {
                        keyValue("stamp_ns", dto.header.stampNS)
                        keyValue("dt_ns", dto.header.dtNS)
                        keyValue("seq", dto.header.seq)
                        keyValue("session_id", dto.header.sessionID)
                        keyValue("clock_domain", dto.header.clockDomain)
                        keyValue("frame_id", dto.header.frameID)
                        keyValue("child_frame_id", dto.header.childFrameID)
                    }

                    section(title: "Status") {
                        keyValue("tracking", dto.status.tracking)
                        keyValue("tracking_confidence", format(dto.status.trackingConfidence))
                        keyValue("num_features", dto.status.numFeatures)
                        keyValue("status_reason", dto.status.statusReason)
                        keyValue("flags", dto.status.flags.joined(separator: ", "))
                    }

                    section(title: "Pose (world → phone)") {
                        keyValue("position", vectorString(dto.poseWorldPhone.position))
                        keyValue("orientation_quat", quaternionString(dto.poseWorldPhone.orientationQuat))
                        keyValue("cov.pos", arrayString(dto.poseWorldPhone.cov.pos))
                        keyValue("cov.ori", arrayString(dto.poseWorldPhone.cov.ori))
                        keyValue("valid", dto.poseWorldPhone.valid)
                    }

                    section(title: "Velocity") {
                        keyValue("world", vectorString(dto.velocity.world))
                        keyValue("source", dto.velocity.source)
                        keyValue("cov", arrayString(dto.velocity.cov))
                        keyValue("valid", dto.velocity.valid)
                    }

                    section(title: "Acceleration") {
                        keyValue("body_no_gravity", vectorString(dto.acceleration.bodyNoGravity))
                        keyValue("world", vectorString(dto.acceleration.world))
                        keyValue("source", dto.acceleration.source)
                        keyValue("cov", arrayString(dto.acceleration.cov))
                        keyValue("valid", dto.acceleration.valid)
                    }

                    section(title: "Gyro") {
                        keyValue("body", vectorString(dto.gyro.body))
                        keyValue("source", dto.gyro.source)
                        keyValue("bias", vectorString(dto.gyro.bias))
                        keyValue("cov", arrayString(dto.gyro.cov))
                        keyValue("valid", dto.gyro.valid)
                    }

                    section(title: "Calibration") {
                        keyValue("T_phone_car.R_rowmajor", arrayString(dto.calib.tPhoneCar.rRowMajor))
                        keyValue("T_phone_car.t", arrayString(dto.calib.tPhoneCar.t))
                        keyValue("world_alignment", dto.calib.worldAlignment)
                        keyValue("world_alignment_detail.y_up", dto.calib.worldAlignmentDetail.yUp)
                        keyValue("world_alignment_detail.z_forward", dto.calib.worldAlignmentDetail.zForward)
                    }

                    section(title: "Origin Reset") {
                        keyValue("origin_id", dto.originReset.originID)
                        keyValue("apply_at_stamp_ns", dto.originReset.applyAtStampNS)
                        keyValue("nonce", dto.originReset.nonce)
                        keyValue("reason", dto.originReset.reason)
                    }

                    section(title: "Integrity") {
                        keyValue("crc32", dto.integrity.crc32)
                    }

                    section(title: "JSON Preview") {
                        Text(dto.jsonString())
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DTO Preview")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        guard !isRunningInPreviews else { return }
                        viewModel.toggleDebugMode()
                    } label: {
                        if viewModel.isDebugMode {
                            Label("디버그 모드", systemImage: "ladybug.fill")
                        } else {
                            Label("디버그 모드", systemImage: "ladybug")
                        }
                    }
                    .tint(viewModel.isDebugMode ? .orange : .primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isCollecting {
                        Button {
                            guard !isRunningInPreviews else { return }
                            viewModel.reset()
                        } label: {
                            Label("세션 리셋", systemImage: "arrow.counterclockwise")
                        }
                    } else {
                        Button {
                            guard !isRunningInPreviews else { return }
                            viewModel.start()
                        } label: {
                            if viewModel.isDebugMode {
                                Label("센서 수집", systemImage: "play.fill")
                            } else if viewModel.isConnecting {
                                Label("연결 중...", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("수집 시작", systemImage: "play.fill")
                            }
                        }
                        .disabled(!viewModel.isDebugMode && viewModel.isConnecting)
                    }
                }
            }
            .onAppear {
                /// 화면이 나타나면 자동 잠금 비활성화
                guard !isRunningInPreviews else { return }
                setIdleTimerDisabled(true)
            }
            .onDisappear {
                /// 화면이 사라지면 센서 수집 중지
                guard !isRunningInPreviews else { return }
                setIdleTimerDisabled(false)
                viewModel.stop()
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func keyValue<T>(_ key: String, _ value: T) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text("\(value)")
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
    }

    private func vectorString(_ vector: TelemetryDTO.Vector3) -> String {
        let x = format(vector.x)
        let y = format(vector.y)
        let z = format(vector.z)
        return "x: \(x), y: \(y), z: \(z)"
    }

    private func quaternionString(_ quat: TelemetryDTO.Quaternion) -> String {
        let x = format(quat.x)
        let y = format(quat.y)
        let z = format(quat.z)
        let w = format(quat.w)
        return "x: \(x), y: \(y), z: \(z), w: \(w)"
    }

    private func arrayString(_ values: [Double]) -> String {
        values.map { format($0) }.joined(separator: ", ")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private var isRunningInPreviews: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
        false
        #endif
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}

#Preview {
    ContentView(viewModel: TelemetryViewModel.preview())
}
