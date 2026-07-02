# VinylPod — 專案記憶核心 (CLAUDE.md)
<!-- Last-verified: 2026-07-01 · 只放「每次對話都必須知道」的事;細節見連結檔 -->

## 專案是什麼
macOS 黑膠風格 Now-Playing 小工具:SwiftUI/AppKit app + 跨瀏覽器擴充套件
(MediaSession 擷取,經 WebSocket bridge 回傳)+ 自動化代理工作流。

## 建置與測試(常用指令)
```bash
swift build                 # 開發建置(SPM,repo 根目錄)
./make_app.sh               # 打包 dist/VinylPod.app
swift build 2>&1 | tail -20 # 快速檢查編譯錯誤
```
- 建置前先確認磁碟空間:`df -h /`(此機器常年 ~97% 滿,I/O error 多半是磁碟滿)。
- 瀏覽器擴充套件在 `BrowserExtension/`;Safari 包裝在 `SafariExtension/`。

## 絕對紅線(違反即停,先問人)
1. **不可修改 `Sources/VinylPod/Core/` 與 `Package.swift`** — 模組契約已凍結,見 CONTRACTS.md。
2. **CLT 環境不能用 `@State` 巨集** — 一律用 `@VPState` 替代(macro 在 CLT 下會炸)。
3. **UI 顏色/圓角/字體不得寫死** — 只能取用 `VPTheme` design tokens。
4. **所有 UI 狀態物件必須 `@MainActor`** — 跨執行緒更新 UI 是 bug,不是風格問題。
5. **不得將憑證、token、`~/.hermes/` 內容寫入 repo 或記憶檔**。
6. 長時間建置、刪檔、對外發布前先向使用者確認。

## 記憶檔案地圖(SSOT 指標,不要複製內容)
| 主題 | 讀哪裡 |
|---|---|
| 架構六大支柱 | `architecture.md` |
| 模組公開介面(凍結契約) | `CONTRACTS.md` |
| 設計 token / 視覺規範 | `design_system.md` |
| 產品需求 | `PRD.md` |
| Widget 功能定義 | `*_features.json` |

## 維護規則(抗 Context Rot)
- 可從程式碼直接推導的事實 → 不寫進記憶檔。
- 每次架構級變更後,更新受影響檔案的 `Last-verified` 日期。
- 記憶檔任一條目與程式碼矛盾時:以程式碼為準,並立即修正記憶檔。
