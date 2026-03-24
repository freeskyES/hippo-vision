# Vision Pro WebRTC 연결 실패 이슈

## 요약

Vision Pro에서 Mac으로의 WebRTC 연결이 실패함. ICE candidate gathering이 visionOS에서 동작하지 않아 미디어 연결이 수립되지 않음.

**상태**: 미해결 (2026-03-24)
**브랜치**: `fix/vision-pro-webrtc`
**관련 브랜치**: `fix/galaxy-xr-webrtc` (Galaxy XR용, 정상 동작)

---

## 증상

- 시그널링(WebSocket)은 정상 연결됨 (offer/answer 교환 성공)
- ICE 연결이 `checking` (state 1)에서 멈추고 `connected`로 진행하지 못함
- Mac에서 `Skipping send - not connected, state: connecting` 무한 반복
- 영상 전송 불가

---

## 디버깅 과정 및 결과

### 1. Developer Strap (유선 연결) 의심 — 실패

**가설**: Vision Pro Developer Strap의 Thunderbolt 브리지가 네트워크 경로를 방해
**테스트**: Developer Strap 제거 후 무선만으로 테스트
**결과**: ❌ 동일한 문제 발생. 유선 연결은 원인이 아님

### 2. 네트워크 서비스 우선순위 — 해당 없음

**가설**: Mac의 Thunderbolt 브리지가 WiFi보다 우선순위가 높아 잘못된 인터페이스로 연결
**확인**: 네트워크 설정에서 서비스 순서 확인 (LG Monitor > Thunderbolt 브리지 > Wi-Fi > AX88179B)
**결과**: Developer Strap 제거해도 동일하므로 근본 원인 아님

### 3. Mac 방화벽 — 해당 없음

**가설**: macOS 방화벽이 UDP 트래픽 차단
**테스트**: 방화벽 활성화/비활성화 테스트
**결과**: ❌ 방화벽 상태와 무관하게 동일한 문제

### 4. ICE candidate 디버깅 로그 추가 — 핵심 발견

**작업**: WebRTCManager.swift에 ICE candidate 상세 로그 추가
- `ICE:local-candidate:` — 생성된 candidate SDP 내용
- `ICE:remote-candidate:` — 수신된 remote candidate
- `GATHERING_STATE:` — ICE gathering 상태 변화
- `PEER_STATE:` — Peer connection 상태

**결과**: ✅ **근본 원인 발견**

#### Mac 측 (정상)
```
GATHERING_STATE: gathering
ICE:local-candidate: candidate:... udp 192.168.50.189:60971 typ host
ICE:local-candidate: candidate:... udp 192.168.50.3:52487 typ host
ICE:local-candidate: candidate:... udp fd24:b093:728::2 typ host
+ TCP candidates 3개
+ STUN srflx candidate 1개
```
→ 총 7~9개 candidate 정상 생성

#### Vision Pro 측 (비정상)
```
ICE gathering state after setLocal: 0    ← "new" 상태에서 변하지 않음
ICE connection state: 0                  ← 또는 1 (checking)
```
→ `ICE:local-candidate generated` 로그 **없음**
→ `GATHERING_STATE:` delegate 콜백 **없음**
→ **candidate 0개 생성**

### 5. STUN 서버 설정 복원 — 실패

**가설**: Vision Pro의 `iceServers = []` (빈 배열)이 원인
**원본 프로젝트 비교**: 원본에는 `stun:stun.l.google.com:19302` 설정 있었음
**수정**: STUN 서버 복원
```swift
// Before (broken)
rtcConfig.iceServers = []

// After (restored)
let stunServer = LKRTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
rtcConfig.iceServers = [stunServer]
```
**결과**: ❌ STUN 서버 복원해도 ICE gathering 여전히 시작 안 됨 (state: 0)

### 6. WebRTC 라이브러리 버전 비교 — 유력 원인

**비교 결과**:

| 패키지 | 원본 (동작) | 현재 (안 됨) |
|--------|------------|-------------|
| webrtc-xcframework | **137.7151.10** | 137.7151.12 |
| client-sdk-swift | **2.10.1** | 2.12.1 |

**결론**: webrtc-xcframework `137.7151.10` → `137.7151.12` 업그레이드 과정에서 visionOS ICE gathering이 깨진 것으로 추정

**상태**: 🔄 다운그레이드 테스트 필요

---

## 근본 원인 분석

### 문제
LiveKitWebRTC (`webrtc-xcframework 137.7151.12`)가 visionOS에서 ICE candidate gathering을 수행하지 못함.

### 세부 사항
1. `setLocalDescription(answer)` 호출 후 ICE gathering state가 `new`(0)에서 변하지 않음
2. `peerConnection(_:didGenerate:)` delegate 콜백이 호출되지 않음
3. `peerConnection(_:didChange newState: LKRTCIceGatheringState)` 콜백도 호출되지 않음
4. Mac 측 candidate는 정상 생성되지만, Vision Pro에서 보내는 candidate가 없어 양방향 ICE 불가

### 이전 버전에서 동작했던 이유 (추정)
- `webrtc-xcframework 137.7151.10`에서는 visionOS ICE gathering이 정상 동작
- 또는 peer-reflexive candidate를 통해 같은 서브넷에서 우회 연결 성공

---

## 코드 변경 이력

### WebRTCReceiver.swift (Vision Pro)
- `origin/develop`과 비교해 **코드 변경 없음** (git diff 확인)
- STUN 서버 설정만 develop과 원본 프로젝트 간 차이 존재
- 이번 브랜치에서 STUN 복원 + 디버깅 로그 추가

### WebRTCManager.swift (Mac)
- Galaxy XR 대응으로 HEVC → H.264 인코더 전환
- 비트레이트/해상도 프리셋 추가 (wifi5GHz, wifiHotspot, wifiHome)
- ICE restart, BWE 힌트 등 추가
- ICE 디버깅 로그 추가

---

## 다음 단계

### 1순위: 라이브러리 다운그레이드 테스트
- [ ] `webrtc-xcframework`를 `137.7151.10`으로 다운그레이드
- [ ] `client-sdk-swift`를 `2.10.1`로 다운그레이드
- [ ] Vision Pro에서 ICE candidate 생성 여부 확인

### 2순위: 대안 접근
- [ ] 수동 ICE candidate 주입 (Bonjour로 발견한 IP 활용)
- [ ] TURN 릴레이 서버 (Mac에 내장) 검토
- [ ] 다른 WebRTC 라이브러리 검토 (google-webrtc 직접 빌드)

---

## 환경 정보

- **Mac**: MacBook Pro, macOS
- **Vision Pro**: Apple Vision Pro, visionOS
- **네트워크**: 동일 WiFi (192.168.50.x), ASUS RT-BE58 Go 5GHz
- **WebRTC 라이브러리**: LiveKitWebRTC (livekit/webrtc-xcframework)
- **시그널링**: 내장 WebSocket 서버 (EmbeddedSignalingServer, port 8080)
- **Bonjour**: `_ws._tcp` 서비스 디스커버리

---

## 브랜치 구조

```
develop
├── fix/galaxy-xr-webrtc     ← Galaxy XR용 (H.264, 비트레이트 최적화) - 정상 동작
└── fix/vision-pro-webrtc    ← Vision Pro용 (ICE 디버깅, 라이브러리 다운그레이드 필요)
```

---

## 참고: 원본 프로젝트 경로

`/Users/eunsong/프로젝트/MacAir/iOS/2025-C6-M2-TeleVision`
- 이 프로젝트에서 Vision Pro WebRTC 정상 동작 확인 (webrtc-xcframework 137.7151.10)
