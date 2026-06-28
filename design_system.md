# VinylPod — "Ai Structuer" Design System

> Status: **DRAFT — awaiting founder sign-off**
> Date: 2026-06-28
> Mood: Dark Minimalist · Calm · Static-landscape aesthetic (暗色极简 · 宁静)

---

## 1. Design Philosophy

> **Stunning enough for the visual lover, simple enough for everyone.**
> Quiet by default. The landscape is the soul; the UI is a whisper of glass on top of it.

---

## 2. Color System (色彩系统)

### Background Mood — Dark Minimalist (暗色极简)
- Base mood is **dark**, anchored by a **static high-quality landscape photograph** (default: **ice mountain 冰山**; others e.g. peach blossom 桃花).
- **The background never changes color with the track** — visual stability is a hard rule.

### Accent Color — Adaptive from Album Art (自适应取色 — option B, scoped)
- **Adaptive accent:** A single dominant color is extracted from the **current album art** and applied **only to small accent elements**:
  - Progress bar fill
  - Active / focused buttons
  - Playback highlight
  - Subtle text glow / outline
- **Scope rule (conflict resolution):** The large landscape background **stays static and uncolored**; only the small accents "breathe" with each track. This preserves the calm while giving every song a touch of identity.
- **Fallback:** A **pure white / translucent-white** accent mode is available as a one-tap fallback if adaptive color ever feels too busy.

### Suggested Tokens (to refine in build)
| Token | Value (placeholder) |
|---|---|
| `--bg-overlay` | `rgba(0,0,0,0.35)` scrim over landscape for legibility |
| `--text-primary` | `#FFFFFF` |
| `--text-secondary` | `rgba(255,255,255,0.65)` |
| `--accent` | *dynamic — extracted from album art* |
| `--accent-fallback` | `rgba(255,255,255,0.9)` |

---

## 3. Typography (字体系统)

- **Family:** Apple standard sans-serif — **SF Pro / system font** (Modern Sans-Serif).
- **Rationale:** Maximum legibility over dark + landscape + glass surfaces; native macOS feel.
- **Hierarchy:**
  - Track title — semibold, larger.
  - Artist / album — regular, secondary opacity.
  - Time / metadata — small, tertiary opacity.

---

## 4. Material & Surfaces (材质)

- **Glassmorphism (磨砂玻璃):** Semi-transparent frosted panels (macOS `NSVisualEffectView`-style blur) layered over the landscape to create depth without blocking the view.
- Panels float as light, translucent layers — never opaque solid blocks.

---

## 5. Shape Language (形状)

- **macOS-native rounded rectangles (圆角矩形)** throughout.
- **Consistent corner radius** across all panels and buttons for visual comfort and cohesion. (Single radius token, e.g. `--radius: 12px`, to be finalized.)

---

## 6. Layout & Navigation (布局与导航)

Four shared-language sizes (same shape, different scale & control density):

| Mode | Layout |
|---|---|
| **Small (小)** | Single play/pause button over landscape + blur layer. |
| **Normal (正常)** | Progress bar · track title/artist · play/pause + skip controls. |
| **Large (大)** | Album art · full track metadata · complete control console. |
| **Desktop Widget (桌面部件)** | Fullscreen / desktop-embedded, visual-first. Controls in a **hover-reveal overlay**. Toggle **front / behind all windows**. |

- **Navigation:** Menu bar dropdown (primary) + keyboard shortcuts (secondary). No persistent chrome that clutters the calm.

---

## 7. Motion & States (动效与状态)

| State | Treatment |
|---|---|
| **Empty (空)** | Static landscape only. **No motion, no dynamic elements.** |
| **Loading (载入)** | **Smooth fade-in.** No spinners, no rotation. Preserves immersion. |
| **Mode switch** | Fluid resize/relayout; **never interrupts playback or background visuals**. |
| **Error / Offline (错误)** | Default: silent fade back to landscape. On user click: reveal reason + Retry/Reconnect. |
| **Desktop Widget controls** | Invisible at rest → gently fade/reveal on mouse hover. |

---

## 8. Imagery Rules (背景图规则)

- Ship a default **ice mountain** background.
- All backgrounds: high-quality, calm, static, non-reactive to audio.
- User-uploaded images allowed; apply a consistent dark scrim + blur layer so UI stays legible regardless of uploaded image.

---

## 9. Accessibility & Legibility

- Maintain a dark scrim/overlay between landscape and text to guarantee contrast on any background.
- System font + high-contrast white text ensures readability for the "general listener" persona.

---

*Prepared by your Professional Project Questioner. Pending founder sign-off before any code is written.*
