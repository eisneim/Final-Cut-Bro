# FCPX-lite 视觉风格规范 (style.md)

> 目标:让自研 UI 在观感上贴近 Final Cut Pro X。
> 所有色值通过对 `design/fcpx_ui.jpg`(3838×2240 retina 截图)**采样取真实 hex** 得到(中位色 + 最高饱和/最亮像素法),非肉眼估计。
> 本文件是 `Sources/FCPXLite/DesignSystem/Tokens.swift` 的来源,改色先改这里再同步到 Tokens。

---

## 1. 主题总览

- **整体**:纯深色专业剪辑界面,几乎无圆角大色块,信息密度高。
- **基调**:中性灰(无明显冷暖偏向),唯一的彩色来自**蓝色 clip**、**黄色选中态**、和素材缩略图自带的色条。
- **层级靠明度区分**,不靠阴影:越靠近内容(预览画布)越黑,面板 chrome 统一一个灰,分隔线比面板略深或略亮 1~2 级。

---

## 2. 颜色令牌 (Color Tokens)

### 2.1 表面 / Surface
| Token | Hex | 用途 |
|-------|-----|------|
| `surface.titlebar` | `#3B3B3B` | 窗口顶部标题栏(最亮的一层) |
| `surface.chrome` | `#212121` | **主面板底色**:工具栏、侧栏、资源管理器、Inspector、时间线工具栏 —— FCPX 招牌灰,绝大多数 chrome 都是它 |
| `surface.canvas` | `#1A1A1A` | 预览画布、clip 标签条等"内容最深处" |
| `surface.effectsPanel` | `#1F1F1F` | 效果浏览器面板(比 chrome 略深半级) |
| `surface.elevated` | `#2C2C2C` | hover / 次级凸起(列表 hover 行、未选中缩略图底) |

### 2.2 文字 / Text
| Token | Hex | 用途 |
|-------|-----|------|
| `text.primary` | `#EAEAEA` | 正文、时间码、主要标签 |
| `text.cool` | `#DCE2FF` | 侧栏资源名(略带冷调的近白) |
| `text.icon` | `#EEEEEE` | 工具栏图标(线性图标的描边色) |
| `text.muted` | `#696969` | 占位/禁用文字(如 Inspector "不检查任何对象") |
| `text.onAccent` | `#FFFFFF` | clip 上的标签文字、播放头 |

### 2.3 强调 / Accent
| Token | Hex | 用途 |
|-------|-----|------|
| `accent.clipBlue` | `#243553` | 时间线视频 clip 默认填充(深蓝) |
| `accent.clipBlueEdge` | `~#3E5E96` | clip 顶部/边缘的略亮蓝(比填充亮一档的描边) |
| `accent.selectYellow` | `#FFD754` | **选中态主色**:资源管理器选中缩略图的黄色粗边框 |
| `accent.selectClipBorder` | `#FFDB86` | 时间线选中 clip 的橙黄描边 |
| `accent.waveform` | `#8C9CBD` | 音频波形(浅蓝灰,画在 clip 内) |
| `accent.playhead` | `#FFFFFF` | 播放头竖线(白);skimmer 另用细红线 `#FF3B30` |

> 注:`accent.clipBlueEdge` 取近似 `#3E5E96`(比填充亮一档的蓝),用于 clip 上沿/选中前的描边。最终以实现时微调为准。

### 2.4 分隔线 / Border
| Token | Hex | 用途 |
|-------|-----|------|
| `border.panel` | `#000000` @ ~50% 或 `#161616` | 面板之间的硬分隔线(比 chrome 深) |
| `border.subtle` | `#2C2C2C` | 列表行分隔、卡片描边(比 chrome 亮) |

---

## 3. 布局结构 (Layout)

整体三横 + 中间三纵:

```
┌──────────────────────────────────────────────────────────────┐ titlebar #3B3B3B
│ ◎◎◎  [工具栏图标]      [格式/项目名]            [视图切换][分享] │ ~6.5% 高, #212121
├──────────┬───────────────────┬─────────────────┬──────────────┤
│ 资源边栏  │   资源管理器        │    预览区        │  Inspector    │
│ Libraries│   Browser          │    Viewer       │  (检查器)     │
│ ~0–10.5% │   ~10.5–30%        │   ~30–83%       │  ~83–100%    │  主区 ~62% 高
│          │  (项目/片段缩略图)   │  (黑画布+播放器)  │              │
├──────────┴───────────────────┴─────────────────┴──────────────┤
│ [索引] [工具]      [时间线: 项目名 ▾  01:01/11:33:08]           │ 时间线工具栏 #212121
├──────────────────────────────────────────────┬───────────────┤
│  时间线 Timeline                                │ 效果浏览器      │
│  ~0–79%  (标尺 + 磁性轨道 + 音频)               │ Effects ~79–  │  底部 ~31% 高
│                                                 │ 100% #1F1F1F  │
└──────────────────────────────────────────────┴───────────────┘
```

**比例(占窗口宽/高,实现时用最小宽度约束 + 可拖拽分隔)**
- 顶部工具栏高:`~52pt`(含红绿灯标题栏一行)
- 主区 : 时间线区 ≈ **62 : 31**(中间夹一条 ~24pt 时间线工具栏)
- 主区横向:`Libraries 200pt | Browser 自适应~280pt | Viewer 弹性最大 | Inspector 320pt`
- 时间线区横向:`Index 40pt | Timeline 弹性 | Effects 360pt`

---

## 4. 字体 (Typography)

- 字体族:系统 **SF Pro / `.system`**(中文走 PingFang SC,跟随系统)。
- 尺寸档:
  | Token | pt | 用途 |
  |-------|----|------|
  | `font.label` | 11 | clip 标签、缩略图名、列表项 |
  | `font.body` | 12 | 侧栏、Inspector 字段 |
  | `font.section` | 11(半粗,字间距+) | "项目 (2)" / "片段 (128)" 分组标题 |
  | `font.timecode` | 13(等宽 `monospaced`) | 时间码 `00:10:47:00` |
  | `font.title` | 13(medium) | 顶部项目名 |
- 权重:界面以 `.regular`/`.medium` 为主,几乎不用粗体。

---

## 5. 组件样式 (Components)

### 5.1 时间线 Clip
- 填充 `accent.clipBlue #243553`,**无圆角或 ~2pt 极小圆角**。
- 顶部一条 `surface.canvas #1A1A1A` 深色标签条,左对齐白字 clip 名(`font.label`)。
- clip 内部上半为缩略图(首帧),下半/音频部分画 `accent.waveform` 波形。
- **选中**:外描边 `accent.selectClipBorder #FFDB86` ~2pt,不改填充。
- 连接片段(connected)挂在主轴上方/下方 lane,视觉与主轴 clip 一致,靠垂直位置区分。

### 5.2 资源管理器缩略图
- 卡片底 `surface.elevated`,缩略图 16:9,下方两行:clip 名 + 角标。
- 缩略图顶部有一条素材自带的**彩色色条**(蓝/橙等,来自 FCPX 角色/标记)。
- **选中**:`accent.selectYellow #FFD754` 粗边框(~3pt)整圈包裹。

### 5.3 侧栏行 (Libraries / 资源列表)
- 行高 ~24pt,左侧 disclosure 三角 + 图标 + `text.cool` 文字。
- 选中行:`accent.clipBlue` 系蓝色高亮条(系统 selection),非黄。
- 分组标题(智能精选等)用图标 + `font.section`。

### 5.4 工具栏
- 底 `surface.chrome`,线性图标 `text.icon #EEEEEE`,无填充按钮。
- 分段控件/下拉用系统样式,弱描边。
- 时间码居中显示 `font.timecode` + `text.primary`。

### 5.5 Inspector
- 底 `surface.chrome`,顶部 tab 行(变换/裁切/...)。
- 空态:居中 `text.muted` "不检查任何对象"。
- 字段:左 label(`text.muted`)右值(`text.primary`),滑块走系统蓝。

---

## 6. 间距与度量 (Metrics)

| Token | 值 | 用途 |
|-------|----|------|
| `space.xs` | 4pt | 图标-文字间距 |
| `space.sm` | 8pt | 卡片内边距 |
| `space.md` | 12pt | 面板内边距 |
| `space.lg` | 16pt | 分组间距 |
| `radius.clip` | 2pt | clip 圆角 |
| `radius.card` | 4pt | 缩略图卡片圆角 |
| `border.width.sel` | 2–3pt | 选中描边 |
| `divider.width` | 1pt | 面板分隔线 |

---

## 7. 同步到代码

落地为 `DesignSystem/Tokens.swift`(`enum Tokens { enum Color/Font/Space ... }`),
配 `Color(hex:)` 扩展。所有视图**只引用 Token,不写裸 hex**(沿用你 feishu/meetingAssitant 的 `DesignSystem/Tokens.swift` + `Controls.swift` 模式)。

> 待办(实现期微调):`accent.clipBlueEdge` 与 `border.panel` 的精确值在真实控件上对照截图再定;深色主题下 1pt 分隔线在 retina 上可能需要 0.5pt。
