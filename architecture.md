# VinylPod — 架構六大支柱 (architecture.md)
<!-- Last-verified: 2026-07-01 · 做架構決策時讀這份;日常指令與紅線見 CLAUDE.md -->

## 系統鳥瞰
```
┌─ 瀏覽器擴充套件 (BrowserExtension/) ── MediaSession 擷取
│        │  WebSocket (lazy connect, idle 時停止重試)
▼        ▼
Bridge ──► Core (NowPlayingService / AppSettings / AppEnvironment)
              │ protocol 注入 (AudioPlaying / MetadataReading / ArtworkColorExtracting)
    ┌─────────┼──────────┬──────────┐
  Audio    Windowing   Views    MenuBar / Hotkeys
              │
        AppKit 視窗層 (small/normal/large/desktopWidget, front/back layer)
```

## 支柱 1 — UI/UX 規範(單一設計語言)
- 所有視覺常數來自 `VPTheme`(顏色、圓角、字級、動畫 spring)。禁止 magic number。
- 視覺風格:liquid-glass(`glassTint`/`glassStroke`/`scrim`),遵循 Apple HIG。
- 完整 token 與版面規則 → `design_system.md`(SSOT,本檔不重複)。
- 新 View 一律讀 `@EnvironmentObject` 的 `NowPlayingService` / `AppSettings`,不自建狀態源。

## 支柱 2 — 執行緒安全(MainActor 紀律)
- 規則:**觸碰 UI 或 ObservableObject 的類別必須標 `@MainActor`**。
- 背景工作(AVAsset 讀取、artwork 色彩萃取、WS 收包)在背景執行,
  結果經 `await MainActor.run` 或 `@MainActor` 方法回主執行緒。
- 禁止用 `DispatchQueue.main.async` 混搭 async/await —— 統一 structured concurrency。
- CLT 限制:`@State` 巨集不可用,以 `@VPState` 替代(見 CLAUDE.md 紅線 2)。

## 支柱 3 — 模組解耦(凍結契約)
- 模組邊界 = 資料夾邊界:`Audio` / `Windowing` / `Views` / `Bridge` / `MenuBar` / `Hotkeys`。
- 模組之間只透過 **Core 的 protocol 與型別**溝通,不得直接 import 彼此的具體類別。
- 公開介面凍結於 `CONTRACTS.md`(SSOT)。要改契約 → 先改 CONTRACTS.md、取得同意、再動程式碼。
- Core 與 `Package.swift` 為唯讀地基。

## 支柱 4 — 外部橋接(Extension ↔ App ↔ MCP)
- 瀏覽器端:免權限 MediaSession 擷取;WS bridge 採 lazy connect,閒置即停止重試(省電)。
- 訊息格式:單向 now-playing 事件流,payload 保持向後相容(只加欄位、不改語意)。
- artwork 品質:高解析升級集中在單一 chokepoint(scraper URL 升級 + app 端 pixel-size normalize),
  新來源接入時必須經過同一 chokepoint,不得各自實作。
- MCP / 代理工作流屬「外圍自動化」:只讀寫 repo 產物,不得成為 app 執行期依賴。

## 支柱 5 — 狀態與設定(單一事實來源)
- 執行期狀態:`AppEnvironment.shared` 是唯一組合根(composition root)。
- 使用者設定:全部集中在 `AppSettings`(UserDefaults 背書),View 不直接碰 UserDefaults。
- 設定項新增流程:`settings_features.json` 定義 → `AppSettings` published → View 綁定。

## 支柱 6 — 建置、發布與環境約束
- 建置鏈:`swift build`(SPM)→ `./make_app.sh` → `dist/VinylPod.app`;Safari 包裝另建。
- 硬約束:機器磁碟常年 ~97% 滿 —— 長建置前先 `df -h`,I/O error 先懷疑磁碟。
- 每個 commit 訊息標明驗證狀態(已建置 / UNVERIFIED),未建置驗證的變更不得聲稱完成。

## 決策紀錄 (ADR-lite)
> 重大取捨用 3 行記在這裡:日期 / 決定 / 為什麼。範例:
- 2026-06-28:app 整併為單一 SPM 專案(原 Xcode 專案封存)— 降低建置摩擦、CLT 可建。
- 2026-06-30:WS bridge 改 lazy connect — 閒置重試耗電且刷 log。
