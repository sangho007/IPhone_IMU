# Telemetry DTO 필드 샘플

> 센서 융합으로 생성된 DTO가 어떤 구조를 따르는지 설명하는 예시 데이터  
> 주석(`//`)은 각 필드의 의미와 값의 범위를 한국어로 설명한다.

```jsonc
{
  // --- 전송 규격 버전. 스키마 변화 시 수신 측 파서 분기 용도 ---
  "schema_version": "1.2.0",

  // --- 샘플의 메타 정보와 좌표계 정의 ---
  "header": {
    "stamp_ns": 0,                    // 나노초 단위 절대 타임스탬프 (clock_domain 기준)
    "dt_ns": 16666666,                // 직전 샘플과의 시간 차이 (60 FPS 기준 ≈ 16.7ms)
    "seq": 0,                         // 전송 순서 추적을 위한 증가 정수
    "session_id": "2025-10-23-rc01",  // 한 세션/주행을 구분하는 토큰
    "clock_domain": "device_monotonic", // 타임스탬프가 속한 시간 기준(모노토닉 등)
    "frame_id": "world",              // 기준 좌표계
    "child_frame_id": "phone"         // 추적 대상(휴대폰) 좌표계 이름
  },

  // --- 트래킹 엔진의 요약 상태 ---
  "status": {
    "tracking": "OK",                 // OK | LIMITED | LOST
    "tracking_confidence": 0.92,      // 추적 신뢰도 0.0~1.0
    "num_features": 310,              // 현재 추적에 쓰인 피처 수
    "status_reason": "low_texture|motion_blur|occlusion|none", // 품질 저하 사유
    "flags": ["NO_JUMP", "NO_RELOCALIZE"] // 추가 상태 플래그 목록
  },

  // --- 월드 기준 폰 자세 추정치 ---
  "pose_world_phone": {
    "position": { "x": 0, "y": 0, "z": 0 }, // 위치 (미터)
    "orientation_quat": { "x": 0, "y": 0, "z": 0, "w": 1 }, // 단위 사원수
    "cov": {
      "pos": [0.01,0.01,0.02],       // 위치 공분산 대각 성분
      "ori": [0.001,0.001,0.001]     // 자세 공분산 대각 성분
    },
    "valid": true                    // 자세 추정 사용 가능 여부
  },

  // --- 월드 좌표계 속도 ---
  "velocity": {
    "world": { "x": 0, "y": 0, "z": 0 },  // m/s
    "source": "ARKit_diff",               // ARKit_diff | IMU_fused | IMU_only
    "cov": [0.02,0.02,0.04],              // 속도 공분산 대각
    "valid": true
  },

  // --- 선형 가속도 (중력 제거) 및 월드 기준 가속도 ---
  "acceleration": {
    "body_no_gravity": { "x": 0, "y": 0, "z": 0 }, // 기기 축 기준 (m/s^2)
    "world": { "x": 0, "y": 0, "z": 0 },           // 월드 축 기준 (m/s^2)
    "source": "CoreMotion",                        // 가속도 추정 출처
    "cov": [0.05,0.05,0.05],                       // 공분산 대각
    "valid": true
  },

  // --- 자이로스코프 ---
  "gyro": {
    "body": { "x": 0.0, "y": 0.0, "z": 0.0 },   // 각속도 rad/s
    "source": "CoreMotion",
    "bias": { "x": 0.0, "y": 0.0, "z": 0.0 },  // 보정된 바이어스 (필요 시)
    "cov": [0.002,0.002,0.002],                // 공분산 대각
    "valid": true
  },

  // --- 기체 ↔ 차량 좌표 변환 및 월드 정렬 ---
  "calib": {
    "T_phone_car": { "R_rowmajor": [ ...9... ], "t": [0,0,0] }, // 3x3 회전, 3x1 병진
    "world_alignment": "gravity", // 월드 정렬 방식 (중력, 마그네틱 등)
    "world_alignment_detail": { "y_up": true, "z_forward": true } // 축 방향 정의
  },

  // --- 좌표계 기준점(origin) 갱신 정보 ---
  "origin_reset": {
    "origin_id": 1,                    // 새 origin 식별자
    "apply_at_stamp_ns": 0,            // 적용 시점 (헤더 clock domain)
    "nonce": "f3c9...",                // 중복 방지 토큰
    "reason": "relocalize|manual|startup" // 초기화 요청 사유
  },

  // --- 무결성 검사 ---
  "integrity": {
    "crc32": "AB12EF34"  // 페이로드에 대한 CRC32 체크섬
  }
}
```
