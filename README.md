# IMU Telemetry Pipeline

iOS에서 수집한 IMU/ARKit 기반 자세 정보를 경량 protobuf 페이로드로 직렬화해 전송하는 샘플 프로젝트다. SwiftUI/ARKit 애플리케이션이 생성한 `TelemetryDTO`를 커스텀 인코더로 변환하고, TCP 스트림을 통해 외부 툴로 전달하는 흐름을 검증한다.

## 구성 요소
- `IMU/TelemetryProtobufEncoder.swift`: DTO를 protobuf wire format으로 직렬화하는 핵심 로직. `docs/TelemetryProtobufEncoder.md`에서 상세 설명을 확인할 수 있다.
- `DTO_Description.md`: DTO 전체 필드 구조와 예시 데이터를 담은 JSONC 문서. 각 필드의 의미는 `docs/DTO_Description.md`에 정리되어 있다.
- `Transport.md`: 전송 프로토콜, 프레이밍, 재시도 규칙 요약. 보충 설명은 `docs/Transport.md`를 참고한다.

## 빌드 및 실행
1. Xcode에서 `IMU.xcodeproj`를 열고 실기기 대상으로 빌드한다. (시뮬레이터에서는 센서 데이터가 제공되지 않는다.)
2. Mac 터미널에서 `iproxy 4820 4820`을 실행해 USB 연결을 통해 TCP 포트를 터널링한다.
3. 앱 실행 후 “수집 시작” 버튼을 누르면 TCP 연결이 수립되고, 30 Hz로 protobuf 페이로드가 전송된다.
4. 수신 측 애플리케이션은 `127.0.0.1:4820`에서 4바이트 Big-Endian 길이 헤더를 읽고, `TelemetryDTO` 스키마에 맞춰 protobuf를 역직렬화한다.

## 테스트 팁
- DTO 구조나 인코더가 변경되면 `DTO_Description.md`와 `docs` 하위 문서를 업데이트해 팀 내 공유를 유지한다.
- 프로토콜 변경 후에는 수신 애플리케이션에서 샘플 데이터를 이용해 파싱 테스트를 실행해 호환성을 검증한다.
