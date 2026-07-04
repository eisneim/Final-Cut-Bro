# Final Cut Bro 🎬🤙

> 一个能被 AI Agent 用大白话完整驱动的 macOS 视频剪辑器。你说人话,它剪片子。
> A macOS video editor your AI can drive with plain words. You talk, bro edits.

<p align="center"><i>「Final Cut Pro 有个兄弟,这个兄弟会替你剪。」<br>"Final Cut Pro has a bro. The bro does the cutting."</i></p>

---

## 这是啥 / What is this

**Final Cut Bro**(原名 FCPX-lite)是一个用 SwiftUI + AppKit 纯手写的 macOS 14 剪辑器,精简克隆了 Final Cut Pro 的磁性时间线。但它真正的野心不是再造一个 FCP——而是造一个**能被对话完整驱动、还能自己测自己**的剪辑环境:每一个编辑操作都是一条可序列化的命令,手动点按钮和 AI Agent 调工具走的是**同一条路**。零外部依赖,纯 Swift Package。

**Final Cut Bro** (formerly FCPX-lite) is a macOS 14 editor hand-written in pure SwiftUI + AppKit, a trimmed-down clone of Final Cut Pro's magnetic timeline. Its real ambition isn't "another FCP" — it's an editing environment that can be **fully driven by conversation and test itself**: every edit is one serializable command, and clicking a button vs. an AI Agent calling a tool go down the **exact same path**. Zero external deps, pure Swift Package.

## 亮点 / Highlights

- 🧲 **磁性时间线** —— spine + 连接片段(字幕/画中画/配乐)、trim/blade/roll/slip/slide、吸附、多轨、转场叠化。
- 🤖 **AI Agent 剪辑** —— 接任意 OpenAI 兼容大模型,用中文说「把废话剪掉、加个字幕、导出成片」,它调工具真的去做。危险操作(写文件/跑命令)先弹确认卡片。
- 🎞 **预览 + 导出共用一套合成管线** —— 自定义 Core Image compositor(变换/裁剪/特效/字幕),导出 H.264 / HEVC / ProRes,或导出 FCPXML 进 Final Cut Pro 接着剪。
- 🌍 **运行时中英切换**(不重启)—— 右上角一个 toggle,想加语言就加。
- 🧪 **能自测** —— DEBUG 下起个本地控制服务器,Agent 能自己驱动 app + 截图自省,做端到端测试。394 个单测护体。

<br>

- 🧲 **Magnetic timeline** — spine + connected clips (subtitles / PiP / music), trim/blade/roll/slip/slide, snapping, multi-lane, cross-dissolve.
- 🤖 **AI Agent editing** — plug in any OpenAI-compatible model, say "cut the filler, add a caption, export it," and it actually calls the tools. Dangerous ops (write file / run command) pop a confirmation card first.
- 🎞 **One compositing pipeline for preview *and* export** — custom Core Image compositor (transform/crop/effects/titles), export H.264 / HEVC / ProRes, or export FCPXML to keep editing in Final Cut Pro.
- 🌍 **Runtime CN/EN switch** (no restart) — one toggle top-right; add more languages whenever.
- 🧪 **Self-testing** — a local control server (DEBUG only) lets the Agent drive the app and screenshot-introspect for end-to-end tests. Backed by 394 unit tests.

## 跑起来 / Run it

```bash
swift build                 # 构建 / build (debug)
swift build -c release      # 构建 / build (release)
swift test                  # 跑全部 394 个测试 / run all 394 tests

bash scripts/run.sh         # debug 版(含 127.0.0.1:8765 自测服务器)/ debug (with self-test server)
bash scripts/run.sh release # release 版(无服务器,日常用)/ release (no server, daily driver)
bash scripts/stop.sh        # 关掉所有实例 + 释放端口 / kill all instances + free the port
bash scripts/make_app.sh    # 打包成 .app / package into .app
```

需要 macOS 14+ 和 Swift 5.9+。想用 AI 剪辑就在「设置」里填一个 OpenAI 兼容的 Base URL / API Key / 模型名——你的 key 只存在本机,不上传任何地方。

Needs macOS 14+ and Swift 5.9+. For AI editing, drop an OpenAI-compatible Base URL / API Key / model in Settings — your key stays **on your machine only**, uploaded nowhere.

## 底层怎么搭的 / How it's wired

**Redux 单向数据流**是整个 app 的脊梁:一切编辑 = `store.dispatch(EditorAction)`,`EditorAction` 是可 Codable 的命令枚举(手动 UI 和 Agent 工具构造的是同一个 action),中央 `dispatch` 把它路由到 `Mutations` 里的**纯函数**去变换时间线。撤销就是快照栈,拖拽会合并成一次撤销。正因为命令是数据,Agent 才能"说一句话 = 发一条命令",测试也能直接喂命令验证。

**Redux one-way data flow** is the app's spine: every edit is `store.dispatch(EditorAction)`, where `EditorAction` is a Codable command enum (manual UI and Agent tools build the *same* action), and a central `dispatch` routes it to **pure functions** in `Mutations` that transform the timeline. Undo is a snapshot stack; a drag coalesces into a single undo. Because commands are data, the Agent can go "one sentence = one command," and tests can feed commands directly.

## 免责 & 现状 / Disclaimer & status

这是个**又菜又爱玩的业余项目**,一半代码是和 AI 结对写出来的,还在快速长身体。能剪、能导、能被 Agent 使唤,但别拿它剪你的婚礼母带——先备份,bro。欢迎 issue / PR / 吐槽。

This is a **scrappy hobby project**, half of it pair-programmed with AI, still growing fast. It cuts, exports, and takes orders from an Agent — but don't cut your wedding master on it yet; back up first, bro. Issues / PRs / roasts welcome.

## 关于这个 bro / About the bro

- 开发者 / Developer: **特里 (Terry)** · spdpd@qq.com
- 交流微信 / WeChat: **spdpd_net**

如果这玩意儿帮你省了几个小时的手动剪辑,给个 ⭐ 就是对 bro 最大的鼓励。

If this thing saved you a few hours of manual trimming, a ⭐ is the biggest bro-love you can give.
