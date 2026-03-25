# WebRTC 인코더 호환성 주의사항

## 핵심 규칙

> **Mac 인코더를 H.264로 변경하면 Vision Pro의 ICE gathering이 동작하지 않는다.**

| Receiver | Mac 인코더 | 결과 |
|----------|-----------|------|
| **Galaxy XR** | `LKRTCDefaultVideoEncoderFactory` (H.264) | ✅ 동작 |
| **Vision Pro** | `HEVCVideoEncoderFactory` (HEVC) | ✅ 동작 |
| **Vision Pro** | `LKRTCDefaultVideoEncoderFactory` (H.264) | ❌ ICE 실패 |

## 배경

2026-03-12 Galaxy XR WebRTC 연동을 위해 Mac 인코더를 HEVC → H.264로 전환했음.
Galaxy XR의 브라우저가 HEVC를 지원하지 않아 H.264가 필요했으나, 이 변경이 Vision Pro의 ICE negotiation을 완전히 깨뜨렸음.

## 현상

H.264 인코더 사용 시 Vision Pro에서:
- SDP offer/answer 교환은 정상
- 하지만 ICE gathering state가 `new`(0)에서 변하지 않음
- ICE candidate가 0개 생성됨
- 결과: WebRTC 미디어 연결 불가

HEVC 인코더 복원 시:
- ICE gathering 즉시 시작 → candidate 생성 → 연결 성공 → 영상 수신

## 브랜치 관리

```
fix/galaxy-xr-webrtc   → H.264 인코더 (Galaxy XR 전용)
fix/vision-pro-webrtc  → HEVC 인코더 (Vision Pro 전용)
```

**두 브랜치의 Mac 인코더 설정을 절대 혼용하지 말 것.**

## 향후 개선 방안

Mac 앱에서 receiver 타입에 따라 인코더를 동적으로 전환하는 방식 검토:
- Receiver 등록 시 디바이스 타입 전달 (Vision Pro / Galaxy XR)
- Mac에서 해당 타입에 맞는 인코더 팩토리 선택
