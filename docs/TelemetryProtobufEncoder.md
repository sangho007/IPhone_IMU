# TelemetryProtobufEncoder.swift 개요

`TelemetryProtobufEncoder`는 `TelemetryDTO` 구조체를 Google Protocol Buffers wire format으로 직렬화하는 경량 인코더다. SwiftProtobuf 라이브러리에 의존하지 않고 필요한 부분만 구현해 iOS 번들 크기를 줄이고 초기화 시간을 단축한다.

## 주요 기능
- 루트 메시지에서 `schema_version`을 문자열로 기록해 수신 측에서 스키마 버전을 식별할 수 있도록 한다.
- `header`, `status`, `pose`, `velocity`, `acceleration`, `gyro`, `calib`, `origin_reset`, `integrity` 등 DTO의 섹션을 필드 번호에 맞춰 protobuf 메시지로 구성한다.
- `ProtoWriter`는 varint, fixed64, length-delimited 필드를 직접 작성하고, `writeVector3`, `writeQuaternion` 같은 도우미 메서드로 반복 코드를 줄인다.

## 동작 흐름
1. `ProtoWriter` 인스턴스를 생성해 직렬화 버퍼를 초기화한다.
2. DTO 각 섹션을 protobuf 필드 규칙에 맞춰 `writeMessage`, `writeString`, `writeDouble`, `writePackedDoubles` 등을 호출해 기록한다.
3. 모든 필드를 순서대로 작성한 뒤 `writer.data`를 반환해 TCP 전송 혹은 파일 저장에 활용한다.

## 확장 시 고려 사항
- DTO 구조가 바뀌면 **필드 번호 재사용 금지** 규칙을 지켜야 한다. 새로운 필드는 기존 번호와 충돌하지 않도록 현재 최대 번호(10) 이후 숫자를 사용한다.
- 그대로 재사용하되 optional 필드만 추가하는 경우, 수신 측 파서는 미지원 필드를 무시하므로 호환성이 유지된다.
- SwiftProtobuf로 교체하려면 schema 정의(`.proto`)를 작성하고 `protoc`로 Swift 코드를 생성해야 하므로 빌드 파이프라인 변화를 고려해야 한다.
