# VinylPod — Product Requirements Document (PRD)

> Status: **HISTORICAL — founding PRD (original intent). The app has since been built (~9,300 LOC Swift + MV3 extension).**
> Date: 2026-06-28 · Reconciled: 2026-07-03
> Phase: Built — current implementation state lives in [`codex.md`](codex.md); this doc is kept for original product intent.
> Platform: macOS native + cross-browser extension

---

## 1. Core Vision (核心愿景)

VinylPod is a **pixel-perfect clone of VinylPod**, built as a **native macOS tool** whose single job is to **capture and beautifully display the currently-playing music**.

The core experience is **minimalist and calm (极简 · 宁静)** — it fuses *practical playback controls* with *static landscape photography* so the app feels less like software and more like a quiet, living piece of desktop decor.

**Guiding design principle (locked):**
> Visually stunning enough to delight a "visual person," yet so simple that *anyone* can use it. Every decision is balanced against these two users.

---

## 2. Target Audience (目标用户)

| Persona | Description | What they need |
|---|---|---|
| **A — Music enthusiasts / visual lovers (音乐发烧友 / 视觉控)** | Love album art, vinyl aesthetics, immersive visuals; treat the app as desktop decor. | Beauty, atmosphere, large immersive modes. |
| **D — General listeners (大众普通听众)** | No strong preferences; "the simpler the better." | Zero learning curve, sensible defaults. |

---

## 3. Music Sources — Unified Now-Playing Layer (音乐来源)

The app ingests **three input sources** and presents them through **one unified "Now Playing" display layer**:

1. **Local MP3 upload / drag-and-drop (本地文件)** — User drags audio files (mp3/flac/etc.) onto the window; the app plays them and reads cover art + metadata from embedded ID3 tags.
2. **Browser-extension web capture (网页捕捉)** — The existing `BrowserExtension/` (MediaSession capture + liquid-glass popup) reports what is playing on websites.
3. **Apple Music + Spotify connect (流媒体连接)** — Reads now-playing state (title, artist, cover, progress) and offers basic transport controls (play/pause, prev/next).

> **Source priority / resolution:** When a local file is actively playing, it takes precedence. Otherwise the app displays the active streaming/web source. (To be finalized in the SPEC phase.)

---

## 4. Window Modes & Layouts (四种形态)

Four runtime-selectable sizes share roughly the same shape and visual language; they differ in size and how many controls are revealed.

| Mode | 中文 | Contents |
|---|---|---|
| **Small** | 小 | **Play/Pause only.** Minimal footprint. |
| **Normal** | 正常 | Progress bar + track info (title/artist) + playback controls. |
| **Large** | 大 | Album art + detailed track metadata + full control console. |
| **Desktop Widget** | 桌面部件 | **Largest** — covers the full screen / embeds into the desktop. Visual-first. Controls are **hidden at rest, revealed on mouse hover**. Can toggle between **in front of all windows** and **behind all windows** (below desktop icons). |

Switching modes **must never interrupt audio playback** or disturb the background visuals.

---

## 5. Mode-Switching Mechanism (切换方式)

**E — Menu bar primary + keyboard shortcuts secondary:**

- **Menu bar dropdown (主):** Click the VinylPod icon in the macOS menu bar → choose size and the Desktop Widget's front/behind layer.
- **Keyboard shortcuts (辅):** e.g. ⌘1 = Small, ⌘2 = Normal, ⌘3 = Large, ⌘4 = Desktop Widget (final keymap in SPEC phase).

---

## 6. User Journey (用户旅程)

1. **Launch (启动):** App opens with the default landscape background (ice mountain), acting as a desktop widget.
2. **Interact (交互):** User drags a music file into the window → app seamlessly switches to playback mode. (Or connects Spotify / Apple Music / a browser tab.)
3. **Experience (体验):** User switches window size (Small → Normal → Large → Desktop Widget) on demand. All operations are fluid and never break the background's visual calm.

---

## 7. States & Edge Cases (状态规范)

| State | Behavior |
|---|---|
| **Empty (空状态)** | Show the selected static landscape background. **No distracting motion / no dynamic elements.** |
| **Loading (载入)** | **Smooth fade-in** — no spinners, no jarring rotation animations. Maintains desktop-immersion. |
| **Error / Offline (错误 / 离线) — option D** | **Silent by default:** smoothly fade back to the plain landscape (empty state). The user can **actively click** to expand the specific reason (e.g. "Spotify not connected") and a **Retry / Reconnect** action. No intrusive popups. |
| **Per-size logic (多尺寸逻辑)** | Small = play/pause only · Normal = + progress + info · Large = + album art + full console · Desktop Widget = visual-first, hover-reveal controls, front/behind toggle. |

---

## 8. Background Imagery (背景图)

- **Default system background:** **Ice mountain (冰山)** landscape photo, high quality.
- **Static:** Background **does not change color with the playing track** — visual stability is a hard rule.
- **User customization:** Users **may upload their own image** to replace the background.

---

## 9. Out of Scope (本期不做 — to confirm)

- Full streaming playback control beyond basic transport (e.g. queue editing, library browsing).
- Cloud upload / cloud sync of local files.
- Social sharing of now-playing.

---

## 10. Open Questions for SPEC Phase

1. Exact source-precedence rules when multiple sources are active simultaneously.
2. Final keyboard keymap.
3. Whether Apple Music / Spotify connection uses OAuth or web-player scraping.
4. Minimum macOS version target.

---

*Prepared by your Professional Project Questioner. Pending founder sign-off before any code is written.*
