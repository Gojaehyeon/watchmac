# watchmac

애플워치를 맥의 무선 미니 모니터로 쓰는 도구입니다.

맥에 워치 화면 비율(0.817)의 가상 디스플레이를 만들고, 그 화면을 30fps로 캡처해서 워치 앱에 HTTP로 송출합니다. 워치는 LAN 또는 Cloudflare 터널로 접속.

```
┌────────────────── MacBook (watchmac) ──────────────────┐         ┌─── Apple Watch ───┐
│  ① 가상 디스플레이 1000×1224 생성   →   ② SCKit 캡처     │         │  WatchMac 앱        │
│      (워치 비율 0.817)                    ↓              │         │   /frame 폴링       │
│                              ③ JPEG 인코딩 (GPU)         │   WiFi  │      ↓              │
│                                          ↓               │  ─────► │   UIImage 디코드    │
│                       ④ HTTP /frame 엔드포인트            │         │   풀스크린 렌더     │
└──────────────────────────────────────────────────────────┘         └─────────────────────┘
```

## 왜 이런 구조

- **가상 디스플레이**: 비공개 `CGVirtualDisplay` API. macOS 26.5 가 너무 작은 가상 디스플레이를 UI 에서 숨기는 동작이 있어, 워치 비율을 유지하면서 사이즈를 1000×1224 로 키움.
- **HTTP 폴링** (WebSocket 아님): watchOS 의 `URLSessionWebSocketTask` 가 personal-team 서명 앱에 막혀 있어서, 단순 GET 으로 우회. 100ms 미만 폴링으로 30fps 까지 동작.
- **Cloudflare 터널**: 셀룰러나 외부망에서 워치 접속용. LAN 안이라면 불필요.

> macOS 26.5 / Apple Watch Ultra 2 / watchOS 26.5 에서 동작 확인됨.

## 요구 사항

- macOS 14 이상 (Apple Silicon 권장)
- Xcode 16 이상 (워치 앱 빌드용)
- 화면 기록 권한 (시스템 설정 → 개인정보 보호 및 보안 → 화면 기록)
- (선택) `cloudflared` — 공개 터널 쓸 때만. `brew install cloudflared`

## 설치 — 맥 메뉴바 앱

### 방법 A — DMG (권장)

[**watchmac.dmg 다운로드**](https://github.com/Gojaehyeon/watchmac/releases/latest) → 열어서 Applications 폴더로 드래그.

Developer ID 서명 + Apple 공증(notarized)된 앱이라 **더블클릭으로 바로 실행**됩니다. Gatekeeper 우회 불필요.

### 방법 B — 직접 빌드

```bash
cd mac
./build-app.sh          # watchmac.app 생성
./make-dmg.sh           # (선택) watchmac.dmg 생성 + 서명 + 공증
```

첫 실행 시 화면 기록 권한 요청. 권한 켠 뒤 한 번 종료하고 다시 여세요.

메뉴에서:
- 상태 (켜짐/꺼짐) · 보는 사람 수
- LAN 주소 (같은 WiFi)
- 공개 주소 (Cloudflare, 가능한 경우)
- 맥에서 미리보기

## 설치 — 워치 앱

```bash
cd watch
xcodegen generate
open WatchMac.xcodeproj
```

Xcode에서:
1. TARGETS → WatchMac → Signing & Capabilities → 본인 Apple ID 선택
2. (페어 아이폰 USB 연결 + 워치/폰 개발자 모드 ON)
3. 디바이스 셀렉터에서 본인 워치 선택 → ▶ Run

처음 실행 시 화면 가운데 탭하면 호스트 입력 시트가 뜸. 맥의 메뉴바 → "주소 복사" 로 복사한 URL을 입력 → 연결.

> 무료 Apple ID 서명은 7일마다 재서명 필요.

## 디렉토리 구조

```
watchmac/
├── mac/                    # macOS 메뉴바 앱
│   ├── Package.swift
│   ├── build-app.sh
│   └── Sources/
│       ├── CVirtualDisplay/   # 비공개 CGVirtualDisplay 브리지
│       └── watchmac/          # Swift 앱 본체
└── watch/                  # watchOS 앱 (Xcode 프로젝트)
    ├── project.yml
    └── App/
        ├── App.swift
        ├── ContentView.swift
        └── WatchStream.swift
```

## 한계 / 주의

- `CGVirtualDisplay` 는 **비공개 API** 입니다. macOS 메이저 업데이트로 깨질 수 있습니다.
- `URLSessionWebSocketTask` 가 막혀 HTTP 폴링으로 동작 — LAN 에서 30fps 가능, 셀룰러는 RTT 에 따라 5~15fps.
- macOS 26.5 의 System Settings → Displays UI 는 가상 디스플레이를 숨길 수 있음. system_profiler 와 WindowServer 레벨에선 등록됨.

## 라이선스

MIT
