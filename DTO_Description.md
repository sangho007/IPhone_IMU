{
  "schema_version": "1.2.0",
  "header": {
    "stamp_ns": 0,
    "dt_ns": 16666666,
    "seq": 0,
    "session_id": "2025-10-23-rc01",
    "clock_domain": "device_monotonic",
    "frame_id": "world",
    "child_frame_id": "phone"
  },

  "status": {
    "tracking": "OK",            // OK | LIMITED | LOST
    "tracking_confidence": 0.92, // 0.0~1.0
    "num_features": 310,
    "status_reason": "low_texture|motion_blur|occlusion|none",
    "flags": ["NO_JUMP", "NO_RELOCALIZE"]
  },

  "pose_world_phone": {
    "position": { "x": 0, "y": 0, "z": 0 },
    "orientation_quat": { "x": 0, "y": 0, "z": 0, "w": 1 },
    "cov": { "pos": [0.01,0.01,0.02], "ori": [0.001,0.001,0.001] }, // 대각만
    "valid": true
  },

  "velocity": {
    "world": { "x": 0, "y": 0, "z": 0 },
    "source": "ARKit_diff",      // ARKit_diff | IMU_fused | IMU_only
    "cov": [0.02,0.02,0.04],
    "valid": true
  },

  "acceleration": {
    "body_no_gravity": { "x": 0, "y": 0, "z": 0 },
    "world": { "x": 0, "y": 0, "z": 0 },
    "source": "CoreMotion",
    "cov": [0.05,0.05,0.05],
    "valid": true
  },

  "gyro": {
    "body": { "x": 0.0, "y": 0.0, "z": 0.0 },   // rad/s
    "source": "CoreMotion",
    "bias": { "x": 0.0, "y": 0.0, "z": 0.0 },  // 옵션
    "cov": [0.002,0.002,0.002],
    "valid": true
  },

  "calib": {
    "T_phone_car": { "R_rowmajor": [ ...9... ], "t": [0,0,0] },
    "world_alignment": "gravity",
    "world_alignment_detail": { "y_up": true, "z_forward": true }
  },

  "origin_reset": {
    "origin_id": 1,
    "apply_at_stamp_ns": 0,
    "nonce": "f3c9...",
    "reason": "relocalize|manual|startup"
  },

  "integrity": {
    "crc32": "AB12EF34"
  }
}