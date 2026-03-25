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

#### 3D 멈춤 원인 분석 (2026-03-25)

**증상**: Split SBS(2D) → Stereo 3D 전환 후 첫 6프레임만 표시되고 멈춤

**로그 증거**:
```
Frame #1~#6: Renderer ready: true    ← 6프레임 정상 enqueue
Frame #7~:   Renderer ready: false   ← 렌더러가 데이터 수신 거부
[Stereo3D] Backpressure: 30 frames skipped (272.7%)
[Stereo3D] Backpressure: 60 frames skipped (146.3%)
[Debug 1~5/10] Renderer not ready for data  ← 영구적으로 복구 안 됨
```

**원인 체인**:
1. `ImmersiveSceneRuntime stopped` — 3D 전환 전에 Immersive Space가 이미 종료됨
2. RealityKit이 VideoPlayerComponent의 프레임을 소비할 수 없음 (렌더링 공간 없음)
3. AVSampleBufferVideoRenderer 내부 버퍼가 6프레임으로 가득 참
4. `ready: false` → 모든 후속 프레임 backpressure 스킵 → 화면 멈춤

**시뮬레이터에서 되는 이유**: 시뮬레이터는 Immersive Space 생명주기가 다르게 동작하여 renderer가 프레임을 계속 소비함

**수정 1 (2026-03-25)**: `ImmersiveSceneRuntime.stop()`에 `ARSessionController.shared.stopARSession()` 추가
- AR tracking timer가 runtime 종료 후에도 계속 돌면서 에러 폭발하던 문제 해결
- `ar_world_tracking_provider` 에러 완전 제거됨
- **하지만 3D 멈춤은 여전히 발생** → AR tracking은 부수적 문제였음

**추가 분석 (2026-03-25)**:
- stereo frame 생성 코드 확인: `CMTaggedDynamicBuffer` + `CMStereoViewComponents` 방식 사용 (정상)
- left/right eye tagging, videoLayerID 설정 모두 정상
- 6프레임까지 `Renderer ready: true`로 정상 enqueue됨
- 7프레임부터 `ready: false` → renderer가 프레임을 소비하지 못함
- `Dimensions: 0×0`으로 보고됨 — sample buffer의 format description 이슈 가능
- **시뮬레이터에서는 같은 코드가 정상 동작** → 실기기의 VideoPlayerComponent 렌더링 파이프라인 차이

**의심 원인**:
1. 실기기에서 CMTaggedBuffer 기반 stereo가 WindowGroup에서 제대로 소비되지 않을 수 있음
2. 원본 프로젝트에서는 MV-HEVC 변환 후 VideoToolbox로 플레이했을 가능성
3. Immersive Space가 아닌 일반 Window에서 stereo 렌더링 시 실기기 제약이 있을 수 있음

**조사 결과 (2026-03-25)**:

1. **원본 프로젝트**: CMTaggedBuffer 방식 + **ImmersiveSpace**에서 렌더링 + HeroEye attachment 있음
2. **Apple 샘플**: MV-HEVC 인코딩 방식 (VideoToolbox, kVTCompressionPropertyKey_MVHEVCVideoLayerIDs)
3. **현재 프로젝트**: CMTaggedBuffer 방식이지만 **WindowGroup**에서 렌더링 → 실기기에서 지원 안 됨

**결론**: CMTaggedBuffer stereo는 ImmersiveSpace에서만 동작. WindowGroup에서는 실기기가 stereo tag를 처리하지 못해 6프레임 후 renderer가 멈춤.

**임시 해결 (2026-03-25)**: renderer flush 복구 메커니즘 추가
- renderer가 30프레임 이상 stuck되면 자동 flush → 복구 → 프레임 재수신
- **결과**: 3D 영상 표시 성공! 단, 실질 ~5-6fps (6프레임 enqueue → 30프레임 스킵 → flush 반복)
- **레이턴시**: 매우 큼 — 해상도를 많이 낮춰도 개선 안 됨 → Vision Pro 렌더링 파이프라인 한계
- **참고**: 원본 프로젝트도 동일한 코드/구조 (WindowGroup). 원래 3D가 실기기에서 완벽하지 않았음

**향후 최적화 방향**:
- [ ] Option A: ImmersiveSpace에서 stereo 렌더링 (RealityKit stereo pipeline 활용)
- [ ] Option B: Mac에서 MV-HEVC 인코딩 후 전송 (Apple 정석 방식, Vision Pro 전용 — Galaxy XR 미지원)
- [ ] Option C: stereo 모드 프레임레이트 제한 (15fps) — renderer 부하 감소
- [ ] Option D: CMTaggedDynamicBuffer → CMTaggedBuffer 변환 시도 (Apple 샘플과 동일한 타입)

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

### 1. Vision Pro 3D 모드 실기기 멈춤 — 원인 특정됨
- **근본 원인**: `ImmersiveSceneRuntime stopped` → Immersive Space가 종료되어 렌더러가 프레임을 소비하지 못함
- 6프레임 enqueue 후 renderer buffer 가득 참 → `ready: false` 영구화
- 2D(Split SBS, Raw Stream)는 정상 (Immersive Space 불필요)
- **TODO**: ImmersiveSceneRuntime stop 원인 코드 분석

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
