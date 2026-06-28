# Agent 端到端测试清单

测试方式:用户 `bash scripts/run.sh` 启动 debug 版(含 127.0.0.1:8765 控制服务器);
Agent 经**真实路径**(`/cmd {op:"agentSend", path:"<指令>"}` → `store.sendAgentMessage()`)执行;
用 `/state`、`/preview`、`/previewFrame`、`/layout` 自省断言。**用户启停 server,Agent 测完即止,不留后台进程。**

工具结构(本次重构后):
- `query_timeline` — 只读状态摘要
- `timeline_edit` — `{type, params}`:insert/append/connect/delete/move/blade/trim/set_gap/position_move
- `clip_adjust` — `{type, params}`:scale/position/crop/opacity/volume
- `navigate` — `{type, params}`:playhead/zoom/tool/select/select_asset/undo/redo/import

> 翻译层(index/秒 → ClipID/Time)可不花 LLM token 单独冒烟:`/cmd {op:"dispatchAction", path:"<type>", index/seconds/lane/width:...}`。
> 真端到端(验证 LLM 选对工具+type+参数)走 `agentSend`。

## 步骤 A:逐动作冒烟(广度)

| 域 | 动作 | 自然语言指令 | 期望(/state 断言) | 结果 |
|----|------|------------|------|------|
| navigate | import | "导入这首音乐 <绝对路径>" | assetLibrary +1 | ⬜ |
| timeline | append | "把素材0加到时间线末尾" | clipCount +1 | ⬜ |
| timeline | insert | "在2秒处插入素材1" | 后续片段右移 | ⬜ |
| timeline | connect | "把素材1叠到3秒处的上层" | 出现连接片段(isConnected) | ⬜ |
| timeline | blade | "在第0段4秒处切一刀" | clipCount +1 | ⬜ |
| timeline | trim | "把第0段尾部修到5秒" | duration 变化 | ⬜ |
| timeline | move | "把第2段移到最前面" | spine 顺序变化 | ⬜ |
| timeline | set_gap | "把那个间隙设成2秒" | gap 时长变 | ⬜ |
| timeline | position_move | "用位置工具把第0段移到10秒" | 源处留 gap | ⬜ |
| timeline | delete | "删掉第1段" | clipCount -1 | ⬜ |
| adjust | scale | "把第0段放大2倍" | scale.width=2 | ⬜ |
| adjust | crop | "把第0段左边裁15%" | crop.left≈288(1920宽) | ⬜ |
| adjust | opacity | "把第0段设成半透明" | opacity=0.5 | ⬜ |
| adjust | volume | "把第0段原声压到20%" | volume=0.2 | ⬜ |
| adjust | position | "把第0段画面右移100px" | transform.position.x=100 | ⬜ |
| navigate | playhead | "跳到3秒" | playhead=3 | ⬜ |
| navigate | zoom | "放大时间线到120px每秒" | pxPerSecond=120 | ⬜ |
| navigate | tool | "切到切割工具" | currentTool=blade | ⬜ |
| navigate | select | "选中第0段" | selectedClipID 非空 | ⬜ |
| navigate | undo | "撤销刚才那步" | 状态还原 | ⬜ |
| adjust | add_effect | "给第0段加高斯模糊" | effects+1 | ⬜ |
| adjust | set_effect_param | "把模糊半径调到20" | params.radius=20 | ⬜ |
| adjust | toggle_enabled | "停用第1段" | enabled=false | ⬜ |
| navigate | export_fcpxml | "导出工程到 ~/Desktop/t.fcpxml" | 文件生成 | ⬜ |
| navigate | export_movie | "把成片导出到 ~/Desktop/out.mp4" | 渲染开始 | ⬜ |

判定:LLM 选对工具名 + type + 翻译正确 + /state 反映预期 = ✅;否则 ❌ 并记原因(选错工具 / type 错 / 参数错 / 翻译错)。

## 步骤 B:真实工作流(深度)

素材来源:`~/Downloads/_temp/音乐风格`(199 个音频)+ 测试视频。

任务示例:
> "把这段视频加到时间线,再导入 <某首歌> 作为背景音乐连接到 0 秒的上层,
> 把视频原声音量压到 20%,然后在第 5 秒切一刀删掉前半段,**最后导出成片到 ~/Desktop/out.mp4**。"

验证点:
- 多步连贯(query → append → import → connect → volume → blade → delete → export_movie)无中途失败
- 最终 `/previewFrame` 有画面;连接的音乐轨进入混音(`/preview` spineClips + audioMix)
- 成片文件生成(~/Desktop/out.mp4 存在且可播放)
- LLM 最后给出一句话总结

结果记录:

(待执行回填)

## 已知翻译层限制

- `move` 经 `dispatchAction` 调试 op 无法测(缺 `toClipIndex` 字段);真 e2e 经 `agentSend` 正常。
- `connect` 要求 `atSeconds` 落在某主轴片段范围内,否则返回"错误:atSeconds 处主轴无片段可挂载"。
