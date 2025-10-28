//
//  TelemetryProtobufEncoder.swift
//  IMU
//
//  Created by Codex on 2025-10-23.
//

import Foundation

/// 간단한 프로토콜 버퍼 인코더 구현 (SwiftProtobuf 없이 사용)
enum TelemetryProtobufEncoder {
    /// TelemetryDTO를 protobuf wire format으로 직렬화해 전송용 `Data`를 생성한다.
    /// 필드 번호는 `DTO_Description.md`와 동일한 구조를 유지해야 한다.
    static func encode(_ dto: TelemetryDTO) -> Data {
        var writer = ProtoWriter() // protobuf 원시 바이트를 순차적으로 쌓는 도우미

        // 1. 루트 메시지의 스키마 버전을 문자열로 기록
        writer.writeString(fieldNumber: 1, value: dto.schemaVersion)

        // 2. 센서 샘플의 메타데이터를 담는 header 메시지
        writer.writeMessage(fieldNumber: 2) { header in
            // 타임스탬프와 샘플 간격은 나노초 단위 정수
            header.writeVarint(fieldNumber: 1, value: UInt64(dto.header.stampNS))
            header.writeVarint(fieldNumber: 2, value: UInt64(dto.header.dtNS))
            // 시퀀스 번호는 재전송 감지 등에 활용
            header.writeVarint(fieldNumber: 3, value: UInt64(dto.header.seq))
            // 세션 구분자 및 좌표계 정보
            header.writeString(fieldNumber: 4, value: dto.header.sessionID)
            header.writeString(fieldNumber: 5, value: dto.header.clockDomain)
            header.writeString(fieldNumber: 6, value: dto.header.frameID)
            header.writeString(fieldNumber: 7, value: dto.header.childFrameID)
        }

        // 3. 트래킹 상태 요약 정보
        writer.writeMessage(fieldNumber: 3) { status in
            // 추적 상태 문자열과 신뢰도(0.0~1.0)
            status.writeString(fieldNumber: 1, value: dto.status.tracking)
            status.writeDouble(fieldNumber: 2, value: dto.status.trackingConfidence)
            // 검출된 피처 수와 부가 상태 설명
            status.writeVarint(fieldNumber: 3, value: UInt64(dto.status.numFeatures))
            status.writeString(fieldNumber: 4, value: dto.status.statusReason)
            // 플래그 배열은 반복된 문자열 필드로 기록
            dto.status.flags.forEach { status.writeString(fieldNumber: 5, value: $0) }
        }

        // 4. 월드 좌표계 기준 폰 자세(pose) 정보
        writer.writeMessage(fieldNumber: 4) { pose in
            pose.writeMessage(fieldNumber: 1) { position in
                // 위치 벡터는 x/y/z 순서의 3중 실수
                position.writeVector3(dto.poseWorldPhone.position)
            }
            pose.writeMessage(fieldNumber: 2) { orientation in
                // 사원수는 x/y/z/w 순서로 고정
                orientation.writeQuaternion(dto.poseWorldPhone.orientationQuat)
            }
            pose.writeMessage(fieldNumber: 3) { cov in
                // 위치/자세 공분산은 packed double 배열
                cov.writePackedDoubles(fieldNumber: 1, values: dto.poseWorldPhone.cov.pos)
                cov.writePackedDoubles(fieldNumber: 2, values: dto.poseWorldPhone.cov.ori)
            }
            // 추정치 유효 여부
            pose.writeBool(fieldNumber: 4, value: dto.poseWorldPhone.valid)
        }

        // 5. 속도 정보 및 신뢰도
        writer.writeMessage(fieldNumber: 5) { velocity in
            velocity.writeMessage(fieldNumber: 1) { world in
                world.writeVector3(dto.velocity.world)
            }
            // 속도 추정 방식과 공분산
            velocity.writeString(fieldNumber: 2, value: dto.velocity.source)
            velocity.writePackedDoubles(fieldNumber: 3, values: dto.velocity.cov)
            velocity.writeBool(fieldNumber: 4, value: dto.velocity.valid)
        }

        // 6. 선가속도(중력 제거) 및 월드 기준 가속도
        writer.writeMessage(fieldNumber: 6) { acceleration in
            acceleration.writeMessage(fieldNumber: 1) { body in
                body.writeVector3(dto.acceleration.bodyNoGravity)
            }
            acceleration.writeMessage(fieldNumber: 2) { world in
                world.writeVector3(dto.acceleration.world)
            }
            // 센서 출처와 공분산, 유효 플래그
            acceleration.writeString(fieldNumber: 3, value: dto.acceleration.source)
            acceleration.writePackedDoubles(fieldNumber: 4, values: dto.acceleration.cov)
            acceleration.writeBool(fieldNumber: 5, value: dto.acceleration.valid)
        }

        // 7. 자이로스코프 데이터 및 바이어스
        writer.writeMessage(fieldNumber: 7) { gyro in
            gyro.writeMessage(fieldNumber: 1) { body in
                body.writeVector3(dto.gyro.body)
            }
            gyro.writeString(fieldNumber: 2, value: dto.gyro.source)
            gyro.writeMessage(fieldNumber: 3) { bias in
                bias.writeVector3(dto.gyro.bias)
            }
            gyro.writePackedDoubles(fieldNumber: 4, values: dto.gyro.cov)
            gyro.writeBool(fieldNumber: 5, value: dto.gyro.valid)
        }

        // 8. 기기-차량 좌표 변환 및 월드 정렬 정보
        writer.writeMessage(fieldNumber: 8) { calib in
            calib.writeMessage(fieldNumber: 1) { transform in
                transform.writePackedDoubles(fieldNumber: 1, values: dto.calib.tPhoneCar.rRowMajor)
                transform.writePackedDoubles(fieldNumber: 2, values: dto.calib.tPhoneCar.t)
            }
            calib.writeString(fieldNumber: 2, value: dto.calib.worldAlignment)
            calib.writeMessage(fieldNumber: 3) { detail in
                // 월드 축 정렬 옵션(좌표계 방향)
                detail.writeBool(fieldNumber: 1, value: dto.calib.worldAlignmentDetail.yUp)
                detail.writeBool(fieldNumber: 2, value: dto.calib.worldAlignmentDetail.zForward)
            }
        }

        // 9. 기준점(origin) 재설정 관련 타이밍 정보
        writer.writeMessage(fieldNumber: 9) { origin in
            origin.writeVarint(fieldNumber: 1, value: UInt64(dto.originReset.originID))
            origin.writeVarint(fieldNumber: 2, value: UInt64(dto.originReset.applyAtStampNS))
            origin.writeString(fieldNumber: 3, value: dto.originReset.nonce)
            origin.writeString(fieldNumber: 4, value: dto.originReset.reason)
        }

        // 10. 메시지 무결성 검사 결과
        writer.writeMessage(fieldNumber: 10) { integrity in
            integrity.writeString(fieldNumber: 1, value: dto.integrity.crc32)
        }

        return writer.data
    }
}

// MARK: - ProtoWriter

private enum WireType: UInt8 {
    // protobuf 정의에서 wire type을 숫자로 매핑
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

private struct ProtoWriter {
    private(set) var data = Data()

    /// fieldNumber와 wire type을 기준으로 protobuf varint를 기록한다.
    mutating func writeVarint(fieldNumber: Int, value: UInt64) {
        guard fieldNumber > 0 else { return }
        writeKey(fieldNumber: fieldNumber, wireType: .varint)
        writeRawVarint(value)
    }

    /// Bool 값을 protobuf varint 표현으로 변환
    mutating func writeBool(fieldNumber: Int, value: Bool) {
        writeVarint(fieldNumber: fieldNumber, value: value ? 1 : 0)
    }

    /// 64비트 실수를 IEEE 754 little endian 바이트로 기록
    mutating func writeDouble(fieldNumber: Int, value: Double) {
        guard fieldNumber > 0 else { return }
        writeKey(fieldNumber: fieldNumber, wireType: .fixed64)
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    /// UTF-8 문자열을 길이-구분(length-delimited) 필드로 기록
    mutating func writeString(fieldNumber: Int, value: String) {
        guard let bytes = value.data(using: .utf8) else { return }
        writeLengthDelimited(fieldNumber: fieldNumber, data: bytes)
    }

    /// 길이 프리픽스 형태의 중첩 데이터 기록 (문자열/하위 메시지 공통 경로)
    mutating func writeLengthDelimited(fieldNumber: Int, data nested: Data) {
        guard fieldNumber > 0 else { return }
        writeKey(fieldNumber: fieldNumber, wireType: .lengthDelimited)
        writeRawVarint(UInt64(nested.count))
        data.append(nested)
    }

    /// double 배열을 packed repeated 형식으로 writeLengthDelimited에 위임
    mutating func writePackedDoubles(fieldNumber: Int, values: [Double]) {
        guard !values.isEmpty else { return }
        var packed = Data()
        packed.reserveCapacity(values.count * MemoryLayout<Double>.size)
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { packed.append(contentsOf: $0) }
        }
        writeLengthDelimited(fieldNumber: fieldNumber, data: packed)
    }

    /// 중첩 메시지를 구성하고 직렬화 결과를 호출자 버퍼에 붙인다.
    mutating func writeMessage(fieldNumber: Int, build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        writeLengthDelimited(fieldNumber: fieldNumber, data: nested.data)
    }

    /// 3차원 벡터를 protobuf 메시지로 기록 (x, y, z 순서 유지)
    mutating func writeVector3(_ vector: TelemetryDTO.Vector3) {
        writeDouble(fieldNumber: 1, value: vector.x)
        writeDouble(fieldNumber: 2, value: vector.y)
        writeDouble(fieldNumber: 3, value: vector.z)
    }

    /// 사원수(x, y, z, w)를 protobuf 메시지로 기록
    mutating func writeQuaternion(_ quat: TelemetryDTO.Quaternion) {
        writeDouble(fieldNumber: 1, value: quat.x)
        writeDouble(fieldNumber: 2, value: quat.y)
        writeDouble(fieldNumber: 3, value: quat.z)
        writeDouble(fieldNumber: 4, value: quat.w)
    }

    /// field number와 wire type을 결합한 key(varint) 작성
    private mutating func writeKey(fieldNumber: Int, wireType: WireType) {
        let key = UInt64(fieldNumber << 3) | UInt64(wireType.rawValue)
        writeRawVarint(key)
    }

    /// 다바이트 varint를 LEB128 방식으로 작성
    private mutating func writeRawVarint(_ value: UInt64) {
        var raw = value
        while true {
            let byte = UInt8(raw & 0x7F)
            raw >>= 7
            if raw == 0 {
                data.append(byte)
                break
            } else {
                data.append(byte | 0x80)
            }
        }
    }
}
