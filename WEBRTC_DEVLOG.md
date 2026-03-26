# WebRTC 개발일지

---

## 2026-03-26: 3D Stereo, 드디어 자연스럽게 흘러나오다

어제(3/25) WebRTC 연결을 복구하고 3D를 겨우 표시하는 데 성공했지만, 영상이 뚝뚝 끊기고 레이턴시가 심했다. 오늘은 그 문제를 파고들어 실질적인 개선을 이뤄냈다.

### CVPixelBufferPool — 2D가 실시간이 됐다

매 프레임마다 `CVPixelBufferCreate()`를 호출해서 left/right eye 버퍼를 새로 할당하고 있었다. 3D 모드에서는 프레임당 2번씩. `CVPixelBufferPool`로 바꾸니 **2D 레이턴시가 체감 불가 수준으로 줄었다**. 거의 실시간. 3D도 개선됐지만 여전히 끊김이 있었다.

### 3D 끊김의 정체 — flush 사이클

3D의 끊김 패턴을 분석해보니 이런 구조였다:

```
6프레임 enqueue → renderer stuck → 30프레임 스킵 → flush → 다시 6프레임 → ...
```

renderer가 stereo tagged frame을 6개까지만 받고 멈춘다. flush해야 다시 받는다. 30프레임(~1초)을 기다린 뒤 flush하니까, 1초 분량의 영상이 통째로 빠지고 다음 장면이 갑자기 나타났다.

flush 주기를 **30 → 6 → 2프레임**으로 줄이니 끊김 간격이 대폭 줄었다. "뚝——뚝——뚝" 에서 "딱딱딱딱"으로 바뀐 느낌.

### DisplayImmediately의 함정

하지만 여전히 자연스럽지 않았다. 15fps로 낮춰도 차이가 없었다. 프레임 수 문제가 아니라 뭔가 근본적인 게 잘못돼 있었다.

2D 경로와 3D 경로를 비교해보니 결정적 차이를 발견했다:

```
2D: kCMSampleAttachmentKey_DisplayImmediately = true  ← 있음
3D: (없음)
```

`DisplayImmediately`가 없으면 `AVSampleBufferRenderSynchronizer`가 프레임의 PTS 시간에 맞춰 표시한다. 그런데 synchronizer는 `time: .zero`에서 시작하고, 프레임 PTS는 `CACurrentMediaTime` 기준 ~9000초대다. synchronizer가 9000초에 도달할 때까지 프레임은 버퍼에 쌓이기만 하고 표시되지 않는다. 이게 6프레임 stuck의 진짜 원인이었다.

그래서 `DisplayImmediately`를 3D 경로에도 추가했더니 동작은 했다. 하지만 6프레임이 한번에 뿌려지고 → 갭 → 다시 6프레임이 뿌려지는 패턴이었다. 마치 슬라이드쇼.

### synchronizer 동기화 — 진짜 해결

`DisplayImmediately`를 다시 제거하고, 대신 **첫 프레임의 PTS에 synchronizer를 동기화**했다:

```swift
synchronizer.setRate(1.0, time: firstFramePTS)
```

이러면 synchronizer가 프레임의 PTS 타임라인 위에서 시작한다. 프레임이 33ms 간격으로 자연스럽게 소비된다. flush 후에도 다음 프레임 PTS에 자동 재동기화되도록 `resetEnqueueCounter()`를 추가했다.

**결과: 3D stereo 영상이 자연스럽게 흘러나왔다.**

### 오늘의 변경 요약

변경 | 효과
--- | ---
CVPixelBufferPool 적용 | 2D 거의 실시간 달성
flush 주기 30→2프레임 | 3D 끊김 간격 대폭 감소
DisplayImmediately → synchronizer PTS 동기화 | 3D 자연스러운 영상 흐름 달성

### 남은 과제

3D는 동작하지만 완전히 매끄럽지는 않다. Vision Pro의 stereo 처리 파이프라인이 Galaxy XR 대비 무겁기 때문이다.

- Vision Pro: SW 디코딩 → CPU에서 SBS 분리(VTPixelTransfer x2) → CMTaggedBuffer 태깅 → enqueue
- Galaxy XR: HW 디코딩 → Surface에 zero-copy → SpatialExternalSurface가 SBS 자동 분리

향후 Phase 2(ImmersiveSpace 렌더링), Phase 3(CompositorServices + Metal)으로 추가 개선 가능. 해상도/파이프라인 스펙 상세는 `RESOLUTION_SPEC.md` 참조.

---

## 프로젝트 현황 (2026-03-26, updated)

Mac 앱에서 카메라 영상을 WebRTC로 스트리밍하여 Vision Pro / Galaxy XR에서 수신하는 시스템.

### 지원 디바이스

| Receiver | 코덱 | 연결 상태 | 비고 |
|----------|------|----------|------|
| Vision Pro (실기기) | HEVC | ✅ 2D 실시간, ✅ 3D 동작 | 3D 추가 최적화 여지 있음 |
| Vision Pro (시뮬레이터) | HEVC | ✅ 2D/3D 동작 | |
| Galaxy XR | H.264 | ✅ 동작 | HW zero-copy 파이프라인 |

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

**추가 수정 (2026-03-25)**: `DisplayImmediately` 추가
- 3D stereo 경로(`enqueueSample`)에 `kCMSampleAttachmentKey_DisplayImmediately = true` 설정
- **원인**: synchronizer가 `time: .zero`에서 시작하나 프레임 PTS가 `CACurrentMediaTime` (~수천초)
  → synchronizer가 해당 시간에 도달할 때까지 프레임을 버퍼에 쌓기만 하고 표시하지 않음
  → 6프레임(버퍼 용량) 후 `ready: false` → 표시도 소비도 안 됨
- 2D 경로에는 이미 있었으나 3D 경로에 누락되어 있었음
- **결과**: 동작 개선 (프레임이 표시됨), 하지만 여전히 레이턴시 큼
- 15fps로 낮춰도 레이턴시 동일 → 프레임 처리량이 아닌 파이프라인 지연

**남은 레이턴시 원인 (확인됨, 2026-03-25)**:

| 병목 | 설명 | 심각도 |
|------|------|--------|
| `processingQueue.sync` | stereo 처리가 동기 큐에서 실행 → 호출 스레드 블로킹 | 높음 |
| VTPixelTransfer ×2 | SBS→left/right 분리에 CPU pixel transfer 2회 실행 | 중간 |
| Renderer stereo 소비 | 실기기에서 CMTaggedBuffer stereo 처리가 mono 대비 매우 느림 | 높음 |
| NV12 버퍼 ×2 생성 | 매 프레임마다 left/right용 CVPixelBuffer 2개 할당 | 낮음 |
| CMReadySampleBuffer 변환 | CMTaggedDynamicBuffer → CMReadySampleBuffer → withUnsafeSampleBuffer | 낮음 |

2D vs 3D 비교: 2D는 VTPixelTransfer 1회 + 단일 프레임 enqueue. 3D는 2회 + tagged 프레임.
15fps로 낮춰도 개선 없음 → 프레임 수가 아닌 **프레임당 처리 비용**이 원인

**향후 최적화 계획** (브랜치: `optimize/stereo-3d-latency`):

Phase 1 — ✅ 완료 (2026-03-26):
- [x] CVPixelBufferPool 적용 (매 프레임 CVPixelBufferCreate ×2 → Pool 재사용)
- **2D 결과**: 레이턴시 체감 거의 없음! 대폭 개선
- **3D 결과**: 동작하나 부분별로 끊김 → Phase 1.5에서 해결

Phase 1.5 — ✅ 완료 (2026-03-26, 브랜치: `experiment/stereo-immersive-space`):
- [x] flush 주기 단축: 30프레임 → 6프레임 → 2프레임
- [x] `DisplayImmediately` 제거 → synchronizer PTS 동기화 방식으로 전환
  - 원인: DisplayImmediately가 6프레임을 한번에 표시 → 끊김
  - 해결: 첫 프레임 PTS에 synchronizer 동기화, flush 후 자동 재동기화
- [x] flush 후 `resetEnqueueCounter()`로 synchronizer 재동기화 보장
- **3D 결과**: 자연스러운 영상 흐름 달성! 실기기에서 3D stereo 동작 확인
- **현재 해상도**: 1280×360 전송 → per eye 640×360 (wifi5GHz 프리셋, downsample 1.5x)
- **비트레이트**: target 5Mbps, max 6Mbps (HEVC 인코딩)

Phase 2 — 중간 리스크:
- [ ] 내시경 stereo를 ImmersiveSurgeryView 안에서 렌더링
      (별도 WindowGroup 대신 surgery ImmersiveSpace 내에서 VideoPlayerComponent)

Phase 3 — 높은 리스크, 최대 성능:
- [ ] CompositorServices + Metal 렌더링 활성화
      (EndoscopeImmersiveSpace.swift에 이미 placeholder 코드 있음)
      M2에서 Metal 렌더링 시 메모리 이슈 있었으나, Vision Pro 자체 성능이므로 Mac 스펙과 무관

참고:
- MV-HEVC 인코딩은 Galaxy XR에서 미지원 → Vision Pro 전용이 됨
- Metal 렌더링 부하는 Mac이 아니라 Vision Pro 쪽
- CVPixelBufferPool은 과거에 사용한 적 있으나 현재 코드에서 누락됨

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

## 해상도 파이프라인 비교 (Vision Pro vs Galaxy XR)

### 해상도 축소 과정

| 단계 | 해상도 (전체) | per eye | 원본 대비 |
|------|-------------|---------|----------|
| Mac 카메라 원본 | 1920×1080 ×2 | 1920×1080 | 100% |
| Half SBS 합성 | 1920×540 | 960×540 | 25% |
| downsample 1.5x 인코딩 | 1280×360 | 640×360 | **11%** |

### Vision Pro vs Galaxy XR 3D 처리 비교

| | **Vision Pro** | **Galaxy XR** |
|---|---|---|
| **코덱** | HEVC (H.265) | H.264 |
| **3D 방식** | CMTaggedBuffer (L/R 분리 후 태깅) | SBS → SpatialExternalSurface (HW 자동 분리) |
| **stereo 분리 주체** | Vision Pro CPU (VTPixelTransfer ×2) | Galaxy XR 하드웨어 (StereoMode.SideBySide) |
| **추가 처리** | VTPixelTransfer + CMTaggedBuffer 생성 | 없음 (SBS 그대로 Surface에 전달) |
| **표시 해상도** | 640×360 per eye | 640×360 per eye |
| **전송 비트레이트** | 5Mbps (HEVC) | 5Mbps (H.264) |

### 해상도 개선 옵션

| 설정 변경 | per eye | 원본 대비 | 리스크 |
|----------|---------|----------|--------|
| downsample 1.0x (제거) | 960×540 | 25% | 인코더 부하↑, VT-CS 에러 가능 |
| Full SBS + downsample 1.5x | 1280×720 | 44% | 비트레이트 2배↑ |
| Full SBS + downsample 1.0x | 1920×1080 | 100% | 매우 높은 대역폭, 인코더 한계 |

---

## 브랜치 구조

```
develop
├── fix/galaxy-xr-webrtc              ← Galaxy XR용 (H.264, client-sdk 2.12.1)
├── fix/vision-pro-webrtc             ← Vision Pro용 (HEVC, client-sdk 2.10.1)
├── optimize/stereo-3d-latency        ← Phase 1 + 1.5 최적화 완료
└── experiment/stereo-immersive-space  ← 실험 (merged)
```

---

## 관련 프로젝트

- **Mac + Vision Pro**: `/Users/eunsong/프로젝트/Work/iOS/hippo-vision`
- **Galaxy XR**: `/Users/eunsong/StudioProjects/galaxy-xr-surgical-viewer`
- **원본 (참고)**: `/Users/eunsong/프로젝트/MacAir/iOS/2025-C6-M2-TeleVision`
