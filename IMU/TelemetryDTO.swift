//
//  TelemetryDTO.swift
//  IMU
//
//  Created by Codex on 2025-10-23.
//

import Foundation

struct TelemetryDTO: Codable {
    var schemaVersion: String
    var header: Header
    var status: Status
    var poseWorldPhone: PoseWorldPhone
    var velocity: Velocity
    var acceleration: Acceleration
    var gyro: Gyro
    var calib: Calibration
    var originReset: OriginReset
    var integrity: Integrity

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case header
        case status
        case poseWorldPhone = "pose_world_phone"
        case velocity
        case acceleration
        case gyro
        case calib
        case originReset = "origin_reset"
        case integrity
    }
}

extension TelemetryDTO {
    struct Header: Codable {
        var stampNS: Int
        var dtNS: Int
        var seq: Int
        var sessionID: String
        var clockDomain: String
        var frameID: String
        var childFrameID: String

        enum CodingKeys: String, CodingKey {
            case stampNS = "stamp_ns"
            case dtNS = "dt_ns"
            case seq
            case sessionID = "session_id"
            case clockDomain = "clock_domain"
            case frameID = "frame_id"
            case childFrameID = "child_frame_id"
        }
    }

    struct Status: Codable {
        var tracking: String
        var trackingConfidence: Double
        var numFeatures: Int
        var statusReason: String
        var flags: [String]

        enum CodingKeys: String, CodingKey {
            case tracking
            case trackingConfidence = "tracking_confidence"
            case numFeatures = "num_features"
            case statusReason = "status_reason"
            case flags
        }
    }

    struct PoseWorldPhone: Codable {
        var position: Vector3
        var orientationQuat: Quaternion
        var cov: Covariance
        var valid: Bool

        enum CodingKeys: String, CodingKey {
            case position
            case orientationQuat = "orientation_quat"
            case cov
            case valid
        }
    }

    struct Velocity: Codable {
        var world: Vector3
        var source: String
        var cov: [Double]
        var valid: Bool
    }

    struct Acceleration: Codable {
        var bodyNoGravity: Vector3
        var world: Vector3
        var source: String
        var cov: [Double]
        var valid: Bool

        enum CodingKeys: String, CodingKey {
            case bodyNoGravity = "body_no_gravity"
            case world
            case source
            case cov
            case valid
        }
    }

    struct Gyro: Codable {
        var body: Vector3
        var source: String
        var bias: Vector3
        var cov: [Double]
        var valid: Bool
    }

    struct Calibration: Codable {
        var tPhoneCar: Transform
        var worldAlignment: String
        var worldAlignmentDetail: WorldAlignmentDetail

        enum CodingKeys: String, CodingKey {
            case tPhoneCar = "T_phone_car"
            case worldAlignment = "world_alignment"
            case worldAlignmentDetail = "world_alignment_detail"
        }
    }

    struct Transform: Codable {
        var rRowMajor: [Double]
        var t: [Double]

        enum CodingKeys: String, CodingKey {
            case rRowMajor = "R_rowmajor"
            case t
        }
    }

    struct WorldAlignmentDetail: Codable {
        var yUp: Bool
        var zForward: Bool

        enum CodingKeys: String, CodingKey {
            case yUp = "y_up"
            case zForward = "z_forward"
        }
    }

    struct OriginReset: Codable {
        var originID: Int
        var applyAtStampNS: Int
        var nonce: String
        var reason: String

        enum CodingKeys: String, CodingKey {
            case originID = "origin_id"
            case applyAtStampNS = "apply_at_stamp_ns"
            case nonce
            case reason
        }
    }

    struct Integrity: Codable {
        var crc32: String
    }
}

extension TelemetryDTO {
    struct Vector3: Codable {
        var x: Double
        var y: Double
        var z: Double
    }

    struct Quaternion: Codable {
        var x: Double
        var y: Double
        var z: Double
        var w: Double
    }

    struct Covariance: Codable {
        var pos: [Double]
        var ori: [Double]
    }
}

extension TelemetryDTO {
    static let sample = TelemetryDTO(
        schemaVersion: "1.2.0",
        header: Header(
            stampNS: 0,
            dtNS: 16_666_666,
            seq: 0,
            sessionID: "2025-10-23-rc01",
            clockDomain: "device_monotonic",
            frameID: "world",
            childFrameID: "phone"
        ),
        status: Status(
            tracking: "OK",
            trackingConfidence: 0.92,
            numFeatures: 310,
            statusReason: "low_texture|motion_blur|occlusion|none",
            flags: ["NO_JUMP", "NO_RELOCALIZE"]
        ),
        poseWorldPhone: PoseWorldPhone(
            position: Vector3(x: 0, y: 0, z: 0),
            orientationQuat: Quaternion(x: 0, y: 0, z: 0, w: 1),
            cov: Covariance(pos: [0.01, 0.01, 0.02], ori: [0.001, 0.001, 0.001]),
            valid: true
        ),
        velocity: Velocity(
            world: Vector3(x: 0, y: 0, z: 0),
            source: "ARKit_diff",
            cov: [0.02, 0.02, 0.04],
            valid: true
        ),
        acceleration: Acceleration(
            bodyNoGravity: Vector3(x: 0, y: 0, z: 0),
            world: Vector3(x: 0, y: 0, z: 0),
            source: "CoreMotion",
            cov: [0.05, 0.05, 0.05],
            valid: true
        ),
        gyro: Gyro(
            body: Vector3(x: 0, y: 0, z: 0),
            source: "CoreMotion",
            bias: Vector3(x: 0, y: 0, z: 0),
            cov: [0.002, 0.002, 0.002],
            valid: true
        ),
        calib: Calibration(
            tPhoneCar: Transform(
                rRowMajor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                t: [0, 0, 0]
            ),
            worldAlignment: "gravity",
            worldAlignmentDetail: WorldAlignmentDetail(yUp: true, zForward: true)
        ),
        originReset: OriginReset(
            originID: 1,
            applyAtStampNS: 0,
            nonce: "f3c9...",
            reason: "relocalize|manual|startup"
        ),
        integrity: Integrity(
            crc32: "AB12EF34"
        )
    )
}

extension TelemetryDTO {
    func jsonString(prettyPrinted: Bool = true) -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        guard let data = try? encoder.encode(self) else {
            return "{}"
        }

        return String(decoding: data, as: UTF8.self)
    }
}
