# 短剧即时互动 · Flutter 客户端

> 参考 [Kazumi](https://github.com/Predidit/Kazumi) 架构构建，与现有 iOS / Web 客户端功能对齐。

## 设计要点

| 关注点 | 选型 | 原因 |
|--------|------|------|
| 视频内核 | **media_kit**（libmpv） | 跨 Android/iOS/macOS/Windows/Linux，原生 HLS + 硬解 |
| 弹幕渲染 | **canvas_danmaku** | 60fps Canvas 渲染，Kazumi 同款 |
| 路由/DI | **flutter_modular** | 与 Kazumi 一致，易扩展子模块 |
| 状态 | **provider + ChangeNotifier**（关键 Store 用 mobx 升级） | 简单可控 |
| 本地存储 | **hive_ce** | Kazumi 同款，比 sqflite 轻量 |
| 网络 | **dio + cookie_jar** | 拦截器、文件下载完整 |
| 骨架屏 | **skeletonizer** | 加载态视觉一致 |
| 手势 HUD | **screen_brightness + flutter_volume_controller** | 左亮右音中拖进度 |
| Material You | **dynamic_color** | 安卓 12+ 取色 |

## 架构（仿 Kazumi `PlayerController` 拆分）

```
PlayerController                ← 聚合器，掌控生命周期
 ├─ PlaybackController          ← media_kit 播放/进度/倍速
 ├─ DanmakuPlayerController     ← canvas_danmaku，按 tick 投递
 └─ InteractionController       ← 高光识别、冲突投票、分支抉择、笑出鹅叫
```

## 与 iOS 客户端的对应

| 模块 | iOS Swift | Flutter Dart |
|------|----------|--------------|
| 主题 | `Theme.swift` | `core/theme.dart` |
| 首页 | `EpisodeListView.swift` | `features/home/home_page.dart` |
| Banner 轮播 | `HeroBannerCarousel` | `features/home/widgets/hero_banner.dart` |
| 剧水平条 | `DramaSectionStrip` | `features/home/widgets/drama_strip.dart` |
| 底部 Tab | `BottomTabBar` | `features/home/widgets/bottom_tab_bar.dart` |
| 播放器 | `PlayerScreen.swift` | `features/player/player_page.dart` |
| ViewModel | `PlayerViewModel.swift` | `controllers/player_controller.dart` (+ 3 subs) |
| 高光面板 | `InteractionOverlay.swift` | `widgets/highlight_panel.dart` |
| 冲突投票 | `ClashVoteModule` | `widgets/highlight_panel.dart` (`_ClashVoteModule`) |
| 分支浮层 | `BranchChoiceOverlay` | `widgets/branch_choice_overlay.dart` |
| 右侧 Rail | `PlayerRightRail` | `widgets/player_right_rail.dart` |
| 笑出鹅叫 | `FloatingHeartsLayer` | `widgets/floating_hearts.dart` |
| 高光列表 | `HighlightListView` | `features/highlights/highlight_list_sheet.dart` |

## 借鉴 Kazumi 扩展的功能

1. **手势 HUD 三段** — 左半屏纵滑改亮度、右半屏纵滑改音量、横滑预览进度（iOS 端尚未实现，Flutter 端先做出来）
2. **弹幕屏蔽词集合** — `DanmakuPlayerController.blockedWords` 即装即用
3. **媒体内核 mpv** — 原生 HLS、ass 字幕、硬解兜底，远胜 AVPlayer / video.js
4. **跨平台一份代码** — 同时跑 Android / iOS / macOS / Windows / Linux
5. **倍速 / 字幕 / 截图反馈** — 后续可直接复用 Kazumi `PlayerPanelController` 的实现

## 待补充功能（参考 Kazumi）

- [ ] WebDAV 同步追剧记录（Kazumi `webdav_client`）
- [ ] 历史播放 + 进度续看（Hive Box 已开）
- [ ] DLNA 投屏（`dlna_dart`）
- [ ] Anime4K 超分（macOS/Linux 桌面端）
- [ ] 弹幕直发后端 → 实时广播给其他观众（WS）

## 跑起来

```bash
cd flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

iOS / macOS 上：先确保后端在 `127.0.0.1:8000`。
Android 模拟器上：`AppConfig.adjustForPlatform()` 自动把 `127.0.0.1` 换成 `10.0.2.2`。
