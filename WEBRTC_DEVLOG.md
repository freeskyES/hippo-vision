# WebRTC 개발일지

---

## 2026-03-30: OTV-S300 3D 내시경 연결 계획 + 수술 전 준비

### OTV-S300 연결 방식 확인

수술실에 Olympus OTV-S300 3D 내시경이 있다. 구형 CV-190(2유닛)과 달리 **단일 유닛에서 SBS 출력**을 지원한다.

```
구형 CV-190:  유닛 2개 → DVI-D 2개 → 캡처카드 2개 → Mac에서 SBS 합성
OTV-S300:    유닛 1개 → DVI-D 1개 (SBS 출력) → 캡처카드 1개 → Mac에서 바로 수신
```

OTV-S300의 DVI-D PORT A에서 SIDE BY SIDE 모드로 설정하면, 좌/우 영상이 한 프레임에 합쳐서 나온다. 우리 파이프라인에 바로 맞는 형태.

### 연결 구성

```
OTV-S300 DVI-D (SBS 모드)
  → DVI→HDMI 패시브 어댑터
  → Elgato 캡처카드 (HDMI 입력)
  → Mac (SBS 프레임 수신)
  → HEVC 인코딩 + WebRTC 전송
  → Vision Pro (3D Stereo 표시)
```

구형 대비 장점:
- 캡처카드 1개 (2개 불필요)
- FrameSync 불필요 (OTV-S300이 동기화된 SBS를 출력)
- SBS 합성 불필요 (이미 합쳐짐)
- 레이턴시 감소 (합성 단계 제거)

### OTV-S300 스펙 조사 결과

OTV-S300의 3D SIDE BY SIDE 모드는 좌/우 영상을 **수평 압축(horizontally compressing)**하여 나란히 배치한다. SBS는 무조건 너비가 절반으로 찌부되는 형태.

출력 해상도 옵션:
- 1080p 모드: 1920x1080 SBS → per eye 960x1080 (너비 절반 압축)
- WUXGA 모드: 1920x1200 SBS → per eye 960x1200 (너비 절반 압축)

출력 인터페이스: DVI-D (PORT A/B), 3G-SDI Level B (SMPTE424M)
3D 포맷: SIDE BY SIDE 또는 LINE BY LINE 선택 가능

### 구형 CV-190 vs 신형 OTV-S300 per eye 비교

항목 | CV-190 (구형) | OTV-S300 (신형)
--- | --- | ---
출력 방식 | 2채널 개별 Full HD | 1채널 SBS (수평 압축)
per eye 원본 | 1920x1080 | 960x1080 (너비 절반)
캡처카드 | 2개 | 1개
Mac 합성 | 필요 (FrameSync + SBS 합성) | 불필요

### Vision Pro / Galaxy XR 최종 표시 해상도 비교

경로 | per eye 원본 | 합성 | downsample 1.5x | 최종 per eye
--- | --- | --- | --- | ---
CV-190 → Mac 합성 | 1920x1080 | Half SBS → 960x540 | 640x360 | **640x360**
OTV-S300 → 직접 수신 | 960x1080 | 불필요 | 640x720 | **640x720**

OTV-S300 경로가 세로 해상도 2배. SBS로 너비는 절반이지만 높이는 1080 그대로 유지되기 때문.
단, Mac 앱이 OTV-S300의 SBS를 Half SBS로 재합성하지 않고 그대로 전송해야 이 이점 유지.

### 확인 필요 사항

- OTV-S300 터치패널에서 3D 모드 + SBS 출력 설정
- DVI→HDMI 패시브 어댑터 준비
- Mac 앱에서 단일 캡처카드 SBS 직접 수신 모드 테스트 (재합성 없이)

### 3D 모델 관련 이슈 (미해결)

- 수술 중 설정/홈 화면 전환 시 3D 모델 사라짐
- 원인: ImmersiveSurgeryView.onDisappear → runtime.stop() → 엔티티 정리
- onDisappear에서 stop() 제거했으나 SwiftUI RealityView 재생성 문제 잔존
- 워크어라운드: 3D 모델 배치 후 홈/설정 화면 전환 금지
- 수술 후 근본 수정 예정

### Public WiFi WebRTC 이슈

- 공용 WiFi에서 ICE candidate 교환은 되지만 연결 실패
- 원인: Public WiFi에서 UDP 포트 차단 추정
- 수술실에서는 전용 WiFi(ASUS RT-BE58 Go 5GHz) 사용 필요

---

## 2026-03-27: 인코더 동적 전환 구현

### 단일 브랜치 통합을 위한 첫 단계

Galaxy XR(H.264)과 Vision Pro(HEVC) 브랜치를 별도로 관리하는 건 피처 추가할 때마다 양쪽에 구현해야 해서 불편했다. receiver가 등록할 때 디바이스 타입을 전달하고, Mac이 그에 맞는 인코더를 자동 선택하도록 구현했다.

### 변경 사항

흐름:
```
Vision Pro 연결:
  VP → register(role: "receiver", device: "visionPro")
  Server → sender: ready(device: "visionPro")
  Mac → HEVC 인코더 선택

Galaxy XR 연결:
  XR → register(role: "receiver")  ← device 없음 → "unknown"
  Server → sender: ready(device: "unknown")
  Mac → H.264 인코더 선택
```

수정 파일:
- `SignalingClient`: `connect(as:device:)` 파라미터 추가
- `WebRTCReceiver`: `device: "visionPro"` 전달
- `EmbeddedSignalingServer`: receiver device를 sender에게 전달
- `SignalingConnection`: `deviceType` 프로퍼티 추가
- `SignalingDelegate`: `didReceiveReceiverReady(device:)` 시그니처 변경
- `WebRTCManager`: `receiverDevice`에 따라 HEVC/H.264 동적 선택
- `StreamingControlViewModel`: `connectedDeviceType` 저장 후 transport에 전달

### 실기기 테스트 결과

- Vision Pro 실기기에서 HEVC 인코더 정상 선택 확인
- 영상 동작 확인 (시뮬레이터 대비 살짝 끊김은 네트워크/ICE 특성)
- Galaxy XR은 기기 미보유로 미테스트 — `unknown` → H.264 선택 로직은 구현 완료

### 라이브러리 버전

현재 `exact 2.10.1` (webrtc-xcframework 137.7151.10)로 고정. Galaxy XR은 Android 별도 프로젝트라 이 버전과 무관.

---

## 작업 리스트

### 우선순위 높음
- [ ] Galaxy XR 실기기 테스트 (동적 전환 H.264 동작 확인)
- [ ] Galaxy XR signaling에 `device: "galaxyXR"` 명시 추가 (현재 unknown으로도 동작)
- [ ] 단일 브랜치 통합: `feat/dynamic-encoder-switching` → `fix/vision-pro-webrtc` → develop merge

### 우선순위 중간
- [ ] 3D stereo 추가 최적화 (Phase 2: ImmersiveSpace / Phase 3: Metal)
- [ ] 해상도 개선 테스트 (downsample 1.0x → per eye 960x540)
- [ ] ICE 연결 속도 개선 (실기기에서 수십초 소요)

### 우선순위 낮음
- [ ] Full SBS 모드 안정화
- [ ] GCC 비트레이트 ramp-up 최적화 (연결 후 1-2Mbps에서 느리게 상승)
- [ ] Instruments 프로파일링 (각 단계별 실제 소요 시간 측정)

### 해상도 개선 관련 메모
- 이전 시도: downsample 1.0x (1920x540@8Mbps) → **VT-CS -12900 에러, 0.3초 만에 인코더 죽음**
- 당시 H.264 인코더 기준. HEVC 인코더에서는 결과가 다를 수 있음
- downsample 2.0x (960x270)는 안정적이나 화질 낮음
- 현재 downsample 1.5x (1280x360)가 안정성/화질 절충안
- **해상도 올리기 전에 레이턴시 최적화가 먼저** — 해상도↑ = 인코딩/전송/디코딩 부하↑ = 레이턴시 악화

---

## 2026-03-27: 왜 Vision Pro는 Galaxy XR보다 느릴까?

### 의문의 시작

실기기 테스트에서 Vision Pro의 레이턴시가 0.1~0.4초 정도 있다. 2D는 네트워크 환경에 따라 딜레이될 때가 있고, 3D는 거기서 0.3초 더 딜레이되는 느낌.

그런데 이상한 점: **핫스팟(Mac↔Vision Pro 직접 연결)과 로컬 네트워크(라우터 경유)에서 체감 차이가 거의 없다.** 오히려 로컬이 더 느린 느낌까지.

Galaxy XR에서는 같은 Mac, 같은 네트워크에서 훨씬 안정적이고 빠른데, Vision Pro만 불안정하다. 왜?

### 핵심 추론: 네트워크가 병목이 아니다

핫스팟은 Mac과 Vision Pro가 직접 연결되므로 네트워크 홉이 최소다. 그런데도 개선이 안 된다는 건:

> **네트워크 전송(B) 단계가 병목이 아니라, Vision Pro 내부 처리(C/D/E)가 병목이라는 뜻이다.**

```
Mac 인코딩(A) → 네트워크(B) → VP 디코딩(C) → stereo 처리(D) → 렌더링(E)
```

네트워크를 아무리 빠르게 해도 C+D+E가 줄지 않으니 체감 차이가 없는 것.

### 근거: Galaxy XR과 파이프라인 비교

같은 네트워크, 같은 Mac, 같은 해상도(1280x360)인데 Galaxy XR이 더 부드러운 이유:

단계 | Galaxy XR | Vision Pro
--- | --- | ---
디코딩(C) | MediaCodec HW 디코더 (<1ms) | LiveKitWebRTC SW 디코더 (5~15ms 추정)
처리(D) | 없음. SBS 그대로 Surface에 전달 | VTPixelTransfer x2 + CMTaggedBuffer 생성
렌더링(E) | Surface zero-copy → 즉시 표시 | AVSampleBufferVideoRenderer + flush 사이클

Galaxy XR은 디코딩된 프레임이 HW에서 Surface로 zero-copy 전달. CPU가 프레임을 한번도 만지지 않는다.

Vision Pro는 SW 디코딩 후 CPU에서 SBS 분리(2회), 태깅, 버퍼 생성, enqueue까지 최소 5번 CPU 작업이 필요하다.

### 가장 큰 용의자: SW HEVC 디코딩

Galaxy XR의 MediaCodec HW 디코더는 프레임당 <1ms. Vision Pro의 LiveKitWebRTC는 소프트웨어 HEVC 디코더를 사용하며, 프레임당 5~15ms 소요 추정.

30fps에서 프레임 간격은 33ms. SW 디코딩에 15ms를 쓰면 남는 시간이 18ms뿐이고, 여기에 stereo 처리까지 하면 파이프라인 전체가 빠듯해진다. 프레임이 밀리기 시작하면 지연이 누적된다.

단, Vision Pro에도 VideoToolbox HW HEVC 디코더가 있다. 현재 LiveKitWebRTC 라이브러리가 이걸 쓰고 있는지, 아니면 SW 폴백을 쓰고 있는지는 프로파일링 없이 확정 불가.

### 해상도 올리기 전에 최적화가 먼저인 이유

현재도 레이턴시 여유가 없는 상태에서 해상도를 올리면:
- 인코딩 시간↑ (Mac)
- 전송 데이터↑ (네트워크)
- 디코딩 시간↑ (Vision Pro)
- VTPixelTransfer 처리 시간↑ (더 큰 버퍼)

전 구간이 느려진다. **먼저 파이프라인을 최적화해서 여유를 만들고, 그 여유분으로 해상도를 올리는 게 맞는 순서.**

### 최적화 방향 (우선순위순)

1. **HW 디코더 확인** — Vision Pro에서 VideoToolbox HW HEVC 디코딩이 가능한지 조사. 가능하다면 LiveKitWebRTC의 SW 디코더를 우회하고 HW 디코더를 직접 사용. Galaxy XR 수준의 디코딩 속도 기대.

2. **Instruments 프로파일링** — 각 단계(디코딩/처리/렌더링)의 실제 소요 시간을 측정해서 정확한 병목 특정. 추측이 아닌 데이터 기반 최적화.

3. **3D stereo Phase 2** — ImmersiveSpace에서 렌더링하면 flush 사이클 제거 가능. 3D 전용 레이턴시 개선.

4. **해상도 올리기** — 위 최적화 완료 후, 여유분으로 downsample 1.0x (per eye 960x540) 시도.

### HW 디코더 조사 결과 (2026-03-27)

현재 `HEVCVideoDecoder.swift`는 **VTDecompressionSession을 사용**하고 있다. 이건 VideoToolbox API로, Apple 하드웨어 디코더를 쓸 수 있는 API다. 하지만 **HW 가속을 명시적으로 요청하지 않고 있었다**:

```swift
// 현재 코드
VTDecompressionSessionCreate(
    decoderSpecification: nil,  // ← nil = 시스템이 HW/SW 알아서 결정
    ...
)
```

`nil`이면 VideoToolbox가 "최적"이라 판단하는 쪽을 선택한다. Vision Pro(M2 칩)에 HEVC HW 디코더가 있지만, 특정 조건에서 SW 폴백할 수 있다.

**즉시 적용 가능한 최적화:**

1. **HW 가속 힌트 추가** — `kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true` 설정. VideoToolbox에 "가능하면 HW 써라"고 명시. 예상 CPU 5% 감소.

2. **GPU 호환 픽셀 버퍼 속성** — `kCVPixelBufferOpenGLESCompatibilityKey`, `IOSurfaceOpenGLESFBOCompatibility` 추가. GPU 전달 효율 개선. 예상 CPU 8% 감소.

3. **디코더 backpressure 프레임 드롭** — VTDecompressionSession에 제출하는 프레임 수를 최대 2개로 제한. 파이프라인이 밀릴 때 프레임 누적 방지. 예상 CPU 15% 감소.

**Galaxy XR 수준(zero-copy) 달성은 구조상 불가:**
- Android: MediaCodec → Surface (1단계, GPU 내부)
- visionOS: VTDecompressionSession → CVPixelBuffer → 처리 → AVSampleBufferVideoRenderer (3단계, CPU 경유)
- visionOS에는 VideoToolbox → RealityKit 직접 Surface 연결 API가 없다

**결론:** HW 디코더 자체는 이미 사용 가능하지만 최적화 여지가 있다. 위 3가지 적용으로 현재 대비 ~20% CPU 사용 감소 예상. Galaxy XR처럼 0-copy는 불가하지만, 레이턴시 여유를 만들어서 해상도 올릴 공간을 확보할 수 있다.

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

### 상세 로그 & 근거

#### 1. CVPixelBufferPool이 왜 효과적이었나

변경 전: 매 프레임 `CVPixelBufferCreate()` 호출. 3D는 left/right 2개라 프레임당 2회.

```swift
// Before — 매번 새 버퍼 할당 (OS에 메모리 요청 → 할당 → 초기화)
var buffer: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs, &buffer)
```

```swift
// After — Pool에서 재사용 (이미 할당된 버퍼 반환, OS 호출 없음)
CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
```

30fps × 2버퍼 = 초당 60회 OS 메모리 할당이 Pool 재사용으로 바뀌니, 2D는 레이턴시가 체감 불가 수준으로 줄었다. 3D도 개선됐지만 다른 병목(synchronizer 타이밍)이 더 컸다.

#### 2. 3D flush 사이클 — 로그 근거

실기기 로그에서 명확하게 보이는 패턴:

```
Frame #1~#6: Renderer ready: true    ← 6프레임 정상 enqueue
Frame #7:    Renderer ready: false   ← stuck 시작
Frame #8:    Renderer ready: false   ← skip
(flush 후)
Frame #9:    Renderer ready: true    ← 복구!
Frame #10:   Renderer ready: true    ← 계속 진행
```

- renderer 내부 버퍼 용량이 약 6프레임
- 프레임이 표시(소비)되지 않으면 버퍼가 차서 `ready: false`
- `flush()`로 버퍼를 비우면 즉시 `ready: true`로 복구
- flush 주기가 길수록(30프레임) 끊김이 길고, 짧을수록(2프레임) 끊김이 짧음

#### 3. DisplayImmediately vs synchronizer — 왜 슬라이드쇼가 됐나

`DisplayImmediately = true`는 "PTS 무시하고 즉시 표시하라"는 의미다. 문제는 renderer가 `ready: true`인 동안 6프레임을 한번에 받아서 한번에 표시한다는 것:

```
[시간 0ms]   Frame 1,2,3,4,5,6 → 한꺼번에 표시 (거의 동시에)
[시간 66ms]  Frame 7,8 → skip (ready: false)
[시간 100ms] flush → ready: true
[시간 100ms] Frame 9,10,11,12,13,14 → 한꺼번에 표시
...반복
```

사용자 눈에는: 6장 한번에 → 빈 구간 → 6장 한번에. 마치 애니메이션 프레임을 넘기는 것처럼 보인다.

#### 4. synchronizer PTS 동기화 — 왜 이게 해결인가

synchronizer는 "시계"다. 프레임의 PTS와 synchronizer의 시계를 맞추면, renderer가 33ms마다 한 프레임씩 꺼내서 표시한다.

```
synchronizer 시작: time = 0초
프레임 PTS:        time = 9589초

→ synchronizer가 9589초에 도달해야 프레임 표시
→ 실시간으로 9589초 걸림 (약 2.6시간)
→ 그 동안 프레임은 버퍼에 쌓이기만 함 → 6개 차면 ready: false
```

해결:

```swift
// 첫 프레임의 PTS에 synchronizer 시계를 맞춤
synchronizer.setRate(1.0, time: firstFramePTS)
// → synchronizer 시계 = 9589초에서 시작
// → 프레임 PTS 9589.000, 9589.033, 9589.067... 순서대로 33ms 간격으로 표시
```

flush 후에는 `resetEnqueueCounter()`로 다음 프레임에서 synchronizer를 재동기화한다.

#### 5. Galaxy XR이 더 부드러운 이유 — 코드 기반 근거

이건 직접 체험이 아니라 코드 분석과 로그에서 추론한 것이다.

Vision Pro 3D 경로 (코드에서 확인):
```
HEVC 비트스트림
  → LiveKitWebRTC SW 디코더 (CPU)          ← CPU 작업 1
  → CVPixelBuffer (CPU 메모리)
  → VTPixelTransferSession #1: left crop   ← CPU 작업 2
  → VTPixelTransferSession #2: right crop  ← CPU 작업 3
  → CVPixelBuffer 2개 생성                 ← 메모리 할당
  → CMTaggedBuffer 태깅                    ← CPU 작업 4
  → CMSampleBuffer 생성                    ← CPU 작업 5
  → AVSampleBufferVideoRenderer enqueue
  → RealityKit 소비 → 디스플레이
```

Galaxy XR 3D 경로 (코드에서 확인):
```kotlin
// StereoHwDecoder.kt
mediaCodec.configure(format, surface, null, 0)  // Surface에 직접 출력
```
```
H.264 비트스트림
  → MediaCodec HW 디코더 (전용 칩)         ← HW 작업 (CPU 불필요)
  → Surface (GPU 메모리, zero-copy)
  → SpatialExternalSurface(SBS 자동 분리)   ← HW 자동
  → 디스플레이
```

Galaxy XR은 CPU가 프레임 데이터를 한번도 만지지 않는다. Vision Pro는 최소 5번 CPU 작업이 필요하다.

비유: Galaxy XR은 컨베이어 벨트(물건이 올라가면 끝까지 자동). Vision Pro는 사람이 중간에서 물건을 받아, 반으로 자르고, 라벨 붙이고, 다음 벨트에 올리는 구조. 사람(CPU)이 병목.

단, VTPixelTransferSession이 실제로 GPU 가속을 쓰는지 CPU에서만 도는지는 Apple이 명시하지 않아 프로파일링 없이 확정 불가.

### 남은 과제

3D는 동작하지만 완전히 매끄럽지는 않다. 향후 Phase 2(ImmersiveSpace 렌더링), Phase 3(CompositorServices + Metal)으로 추가 개선 가능. 해상도/파이프라인 스펙 상세는 `RESOLUTION_SPEC.md` 참조.

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
