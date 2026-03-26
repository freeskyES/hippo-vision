# 해상도 & 파이프라인 스펙 비교

## Vision Pro 모드별 해상도

```
Mac 카메라:      1920x1080 (양쪽)
SBS 합성:       1920x540 (Half SBS)
HEVC 인코딩:    1280x360 (downsample 1.5x)
WebRTC 전송:    1280x360

Vision Pro 수신: 1280x360 (모든 모드 동일한 입력)
```

모드 | 처리 | 표시 해상도 | 설명
--- | --- | --- | ---
Raw Stream | 처리 없이 그대로 전달 | 1280x360 | SBS 그대로 한 화면에 좌우 나란히
Split SBS | left eye만 추출 | 640x360 | 왼쪽 눈 영상만 2D로 표시
Stereo 3D | left/right 분리 + stereo tag | 640x360 x2 (per eye) | 각 눈에 640x360씩 스테레오

3D 모드에서 각 눈 앞에 640x360 해상도가 표시됨.

---

## Galaxy XR 모드별 해상도

```
Mac 카메라:      1920x1080 (양쪽)
SBS 합성:       1920x540 (Half SBS)
H.264 인코딩:   1280x360 (downsample 1.5x)
WebRTC 전송:    1280x360

Galaxy XR 수신:  1280x360 (MediaCodec H.264 HW 디코딩, zero-copy)
```

모드 | 처리 | 표시 해상도 | 설명
--- | --- | --- | ---
2D | 처리 없이 SurfaceView에 전달 | 1280x360 | SBS 그대로 표시
3D Stereo | SpatialExternalSurface(StereoMode.SideBySide) | 640x360 x2 (per eye) | XR 프레임워크가 SBS 자동 분리

---

## 해상도 축소 과정 (전체 파이프라인)

```
[Mac 카메라]
양쪽 각 1920x1080 (원본)

      | Half SBS 합성 (좌우 50% 축소 후 나란히 배치)
      v

[SBS 프레임]
1920x540 (각 눈: 960x540)
-> 원본 대비: 50% 너비, 50% 높이 = 25% 면적

      | WebRTC downsample 1.5x
      v

[인코딩/전송]
1280x360 (각 눈: 640x360)
-> 원본 대비: 33% 너비, 33% 높이 = 11% 면적

      | 수신 디바이스
      v

[3D Stereo 표시]
각 눈: 640x360
```

단계 | 해상도 (per eye) | 원본 대비 | 축소 원인
--- | --- | --- | ---
카메라 원본 | 1920x1080 | 100% | -
Half SBS 합성 | 960x540 | 25% | 좌우 합치기 위해 각각 절반으로
downsample 1.5x | 640x360 | 11% | 인코더 안정성 + 대역폭

원본 1920x1080 -> 최종 640x360, 면적 기준 약 1/9로 축소.

---

## Vision Pro vs Galaxy XR 비교

항목 | Vision Pro | Galaxy XR
--- | --- | ---
코덱 | HEVC (H.265) | H.264
Mac 인코더 | HEVCVideoEncoderFactory | LKRTCDefaultVideoEncoderFactory
전송 해상도 | 1280x360 | 1280x360
전송 비트레이트 | 5Mbps target / 6Mbps max | 5Mbps target / 6Mbps max
디코더 | LiveKitWebRTC HEVC 소프트 디코더 | MediaCodec H.264 하드웨어 디코더
디코딩 경로 | SW 디코딩 -> CVPixelBuffer | HW 디코딩 -> Surface (zero-copy)
3D stereo 분리 | Vision Pro CPU (VTPixelTransfer x2) | Galaxy XR HW 자동 분리
3D 방식 | CMTaggedBuffer (L/R 분리 후 태깅) | SBS -> SpatialExternalSurface (StereoMode.SideBySide)
추가 처리 | VTPixelTransfer + CMTaggedBuffer 생성 | 없음 (SBS 그대로 Surface에 전달)
3D 표시 해상도 | 640x360 per eye | 640x360 per eye
2D 표시 해상도 | 1280x360 (Raw) / 640x360 (Split) | 1280x360

---

## Galaxy XR SpatialExternalSurface 상세

- 메인 3D: 1600dp x 900dp (StereoMode.SideBySide)
- 수술 AR 오버레이: 800dp x 450dp (StereoMode.SideBySide, z=-400dp)
- SceneCore 폴백: SurfaceEntity 1.2m x 0.675m (StereoMode.SIDE_BY_SIDE)

StereoMode.SideBySide 동작 원리:
- 입력: 1280x360 SBS 프레임
- 프레임워크가 너비를 2로 나눔
- Left eye: pixels [0:640, 0:360]
- Right eye: pixels [640:1280, 0:360]
- 각 눈에 IPD 오프셋 적용 후 표시

---

## 해상도 개선 옵션

설정 변경 | per eye 해상도 | 원본 대비 | 리스크
--- | --- | --- | ---
downsample 1.0x (제거) | 960x540 | 25% | 인코더 부하 증가, 이전에 VT-CS 에러 발생
Full SBS + downsample 1.5x | 1280x720 | 44% | 비트레이트 2배 필요
Full SBS + downsample 1.0x | 1920x1080 | 100% | 매우 높은 대역폭, 인코더 한계

---

## 핵심 인사이트

1. 양쪽 디바이스 모두 최종 per eye 640x360으로 동일하지만, 처리 경로가 다름
2. Galaxy XR: zero-copy HW 디코딩 + HW stereo 분리 = 낮은 레이턴시
3. Vision Pro: SW 디코딩 + CPU stereo 분리 (VTPixelTransfer x2) = 추가 오버헤드
4. Vision Pro에서 Galaxy XR처럼 SBS를 그대로 넘기고 HW 분리하는 방법이 있다면 레이턴시 대폭 개선 가능
