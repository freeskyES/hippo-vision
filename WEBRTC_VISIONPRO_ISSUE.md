# Vision Pro WebRTC 연결 이슈 — 해결됨

## 요약

Vision Pro에서 Mac으로의 WebRTC 연결이 실패했던 이슈. Mac의 인코더를 H.264로 변경한 것이 근본 원인이었음.

**상태**: ✅ 해결 (2026-03-25)
**브랜치**: `fix/vision-pro-webrtc`
**관련 브랜치**: `fix/galaxy-xr-webrtc` (Galaxy XR용, H.264 인코더 사용)

---

## 근본 원인 (확정)

**Mac의 인코더 팩토리가 `HEVCVideoEncoderFactory` → `LKRTCDefaultVideoEncoderFactory` (H.264)로 변경되면서 Vision Pro의 ICE gathering이 동작하지 않았음.**

### 원인 상세

Galaxy XR 대응 과정에서 Mac 인코더를 H.264로 전환했는데, 이 변경이 SDP의 코덱 협상 구조를 바꿔 Vision Pro 측 WebRTC ICE gathering 프로세스가 시작되지 않는 문제를 발생시킴.

```swift
// ❌ H.264 인코더 — Vision Pro ICE gathering 안 됨
let encoderFactory = LKRTCDefaultVideoEncoderFactory()

// ✅ HEVC 인코더 — Vision Pro ICE gathering 정상 동작
let encoderFactory = HEVCVideoEncoderFactory()
```

### 증거

H.264 인코더 사용 시:
```
ICE gathering state after setLocal: 0    ← gathering 시작 안 됨
ICE:local-candidate generated 로그 없음
```

HEVC 인코더 복원 후:
```
ICE gathering state after setLocal: 1    ← gathering 시작!
GATHERING_STATE:1 (gathering)
ICE:local-candidate generated: candidate:... 172.30.47.23 typ host
GATHERING_STATE:2 (complete)
ICE_STATE:2                              ← connected!
WebRTC connection established!
```

---

## 핵심 교훈

> **Mac의 인코더 팩토리 변경이 Vision Pro의 ICE negotiation에 영향을 미친다.**
> Galaxy XR용 H.264와 Vision Pro용 HEVC는 별도 브랜치에서 관리해야 함.

### Galaxy XR vs Vision Pro 차이

| 항목 | Galaxy XR | Vision Pro |
|------|-----------|------------|
| **브랜치** | `fix/galaxy-xr-webrtc` | `fix/vision-pro-webrtc` |
| **Mac 인코더** | `LKRTCDefaultVideoEncoderFactory` (H.264) | `HEVCVideoEncoderFactory` (HEVC) |
| **Receiver 디코더** | 브라우저 기본 (H.264) | `HEVCVideoDecoderFactory` (H.265 + H.264) |
| **라이브러리 버전** | client-sdk-swift 2.12.1 | client-sdk-swift 2.10.1 |

---

## 디버깅 과정 (시간순)

### 시도 1: Developer Strap 제거 — ❌
- 가설: 유선 연결이 네트워크 경로 방해
- 결과: 동일한 문제. 원인 아님

### 시도 2: Mac 방화벽 확인 — ❌
- 가설: UDP 트래픽 차단
- 결과: 방화벽과 무관

### 시도 3: ICE candidate 디버깅 로그 추가 — ✅ 핵심 발견
- Mac은 candidate 정상 생성 (7~9개)
- Vision Pro는 candidate 0개 — ICE gathering 자체가 안 됨
- `ICE gathering state: 0` (new)에서 변하지 않음

### 시도 4: STUN 서버 복원 — ❌
- 원본에 있던 `stun.l.google.com` 복원
- 결과: 여전히 gathering 안 됨

### 시도 5: 라이브러리 다운그레이드 — ❌
- webrtc-xcframework 137.7151.10, client-sdk-swift 2.10.1로 고정
- 결과: 여전히 gathering 안 됨

### 시도 6: `continualGatheringPolicy` 제거 — ❌
- 원본에 없던 설정 제거
- 결과: 여전히 gathering 안 됨

### 시도 7: `IceRestart` 제거/복원 — ❌
- createOffer()의 ICE restart 관련 코드 제거/복원
- 결과: candidate 재생성에 필요하지만 근본 원인 아님

### 시도 8: Mac 인코더 HEVC 복원 — ✅ 해결!
- `LKRTCDefaultVideoEncoderFactory()` → `HEVCVideoEncoderFactory()`
- **즉시 ICE gathering 시작, candidate 생성, 연결 성공, 영상 수신 확인**

---

## 현재 코드 상태 (fix/vision-pro-webrtc)

### WebRTCManager.swift (Mac)
- ✅ HEVC 인코더 사용
- ✅ ICE restart + candidate 디버깅 로그
- ✅ BWE 힌트, stats 수집

### WebRTCReceiver.swift (Vision Pro)
- ✅ STUN 서버 설정 (`stun.l.google.com`)
- ✅ ICE/gathering/candidate 디버깅 로그
- ✅ HEVC 디코더 팩토리

### 라이브러리 버전
- client-sdk-swift: 2.10.1 (exact)
- webrtc-xcframework: 137.7151.10

---

## 브랜치 구조

```
develop
├── fix/galaxy-xr-webrtc     ← Galaxy XR용 (H.264 인코더) - 별도 관리
└── fix/vision-pro-webrtc    ← Vision Pro용 (HEVC 인코더) - ✅ 동작 확인
```

---

## 참고

- 원본 프로젝트: `/Users/eunsong/프로젝트/MacAir/iOS/2025-C6-M2-TeleVision`
- Galaxy XR 브랜치에서 Vision Pro 테스트 시 반드시 인코더를 HEVC로 전환해야 함
- 향후 Mac 앱에서 receiver 타입(Galaxy XR / Vision Pro)에 따라 인코더를 동적 전환하는 것을 검토
