# WebRTC 개발일지

## 프로젝트 현황 (2026-03-25)

Mac 앱에서 카메라 영상을 WebRTC로 스트리밍하여 Vision Pro / Galaxy XR에서 수신하는 시스템.

### 지원 디바이스

| Receiver | 코덱 | 연결 상태 | 비고 |
|----------|------|----------|------|
| Vision Pro (실기기) | HEVC | ✅ 2D 동작, ❌ 3D 멈춤 | 시뮬레이터에서는 3D도 동작 |
| Vision Pro (시뮬레이터) | HEVC | ✅ 2D/3D 동작 | |
| Galaxy XR | H.264 | ✅ 동작 | 브라우저 기반 수신 |

---

## 2026-03-25: Vision Pro WebRTC 연결 복구

### ICE 연결 실패 → 해결

**근본 원인**: Galaxy XR 대응(3/12)으로 Mac 인코더를 HEVC → H.264로 전환한 것이 Vision Pro ICE gathering을 깨뜨림.

**해결**: Mac 인코더를 `HEVCVideoEncoderFactory`로 복원

**디버깅 과정** (8단계):
1. Developer Strap 제거 → ❌
2. Mac 방화벽 확인 → ❌
3. ICE candidate 로그 추가 → Vision Pro candidate 0개 발견
4. STUN 서버 복원 → ❌
5. 라이브러리 다운그레이드 (137.7151.10) → ❌
6. continualGatheringPolicy 제거 → ❌
7. IceRestart 제거/복원 → ❌
8. **Mac 인코더 HEVC 복원 → ✅ 즉시 해결**

상세: `WEBRTC_VISIONPRO_ISSUE.md`

### 인코더 호환성 규칙 (중요)

```
Galaxy XR  → Mac은 H.264 인코더 필수 (HEVC 미지원)
Vision Pro → Mac은 HEVC 인코더 필수 (H.264 시 ICE 실패)
```

**향후 계획**: receiver 등록 시 디바이스 타입 전달 → Mac에서 인코더 동적 전환 → 단일 브랜치 통합

---

## 2026-03-25: 실기기 테스트 결과

### 환경

- Mac: MacBook Pro M5 64GB
- Vision Pro: Apple Vision Pro (실기기, Developer Strap 연결)
- 네트워크: 동일 WiFi (ASUS RT-BE58 Go 5GHz)

### 2D 스트리밍 (Split SBS 모드)

- **상태**: ✅ 동작
- **레이턴시**: 약 0.5초 이내
- Galaxy XR 대비 딜레이가 다소 있음

### 3D 스트리밍 (Stereo 3D 모드)

- **상태**: ❌ 실기기에서 멈춤 (영상 표시 안 됨)
- 시뮬레이터에서는 정상 동작
- 원인 미확인 — 추가 디버깅 필요

### 레이턴시 관련 메모

- MacBook Air (M3?) → MacBook Pro (M5 64GB) 변경 후 레이턴시 체감 감소
- 단, 해상도도 함께 낮췄기 때문에 (downsample 1.5x) 정확한 원인 특정 필요
- 가능한 원인들:
  - Mac 하드웨어 성능 (인코딩 속도)
  - 해상도 감소 (1920×540 → 1280×360)
  - HEVC vs H.264 인코더 성능 차이
  - 네트워크 대역폭
- **TODO**: 동일 해상도에서 Mac 간 비교 테스트 필요

---

## 2026-03-12 ~ 03-24: Galaxy XR WebRTC 연동

### 주요 변경사항

1. Mac 인코더 HEVC → H.264 전환 (Galaxy XR 브라우저 호환)
2. WiFi 프리셋 추가 (wifi5GHz, wifiHotspot, wifiHome)
3. 비트레이트/해상도 최적화
   - wifi5GHz: target 5Mbps, max 6Mbps, downsample 1.5x
   - wifiHotspot: target 1.5Mbps, max 2.5Mbps
4. BWE 초기 비트레이트 힌트 추가
5. GCC freeze 디버깅 및 해결

---

## 미해결 이슈

### 1. Vision Pro 3D 모드 실기기 멈춤
- 시뮬레이터에서는 동작하나 실기기에서 영상이 멈춤
- 2D(Split SBS)는 정상
- 원인 탐구 필요

### 2. 인코더 동적 전환 미구현
- 현재 Galaxy XR / Vision Pro 별도 브랜치로 관리
- receiver 디바이스 타입에 따른 인코더 동적 전환 필요
- 구현 시 단일 브랜치로 통합 가능

### 3. 레이턴시 최적화
- Vision Pro에서 ~0.5초 딜레이
- Galaxy XR 대비 느린 원인 파악 필요
- Mac 하드웨어 vs 해상도 vs 코덱 영향 분리 테스트 필요

---

## 브랜치 구조

```
develop
├── fix/galaxy-xr-webrtc     ← Galaxy XR용 (H.264, client-sdk 2.12.1)
└── fix/vision-pro-webrtc    ← Vision Pro용 (HEVC, client-sdk 2.10.1)
```

---

## 관련 프로젝트

- **Mac + Vision Pro**: `/Users/eunsong/프로젝트/Work/iOS/hippo-vision`
- **Galaxy XR**: `/Users/eunsong/StudioProjects/galaxy-xr-surgical-viewer`
- **원본 (참고)**: `/Users/eunsong/프로젝트/MacAir/iOS/2025-C6-M2-TeleVision`
