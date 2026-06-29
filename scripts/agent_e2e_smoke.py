#!/usr/bin/env python3
"""T7/T8 Agent 端到端冒烟:经真实 LLM(agentSend)逐条发指令,轮询 /state 断言。
用法:先由调用方启动 debug server(:8765),本脚本只发请求 + 断言 + 打印表格。
"""
import json, sys, time, urllib.request

BASE = "http://127.0.0.1:8765"
VIDEO = "/Users/teli/Downloads/tstvideo_副本.mp4"
MUSIC = "/Users/teli/Downloads/_temp/音乐风格/Daya - Hide Away (Virtu Remix).mp3"

def cmd(op, **kw):
    body = json.dumps({"op": op, **kw}).encode()
    req = urllib.request.Request(BASE + "/cmd", data=body, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=60).read())
    except Exception as e:
        return {"_err": str(e)}

def state():
    try:
        return json.loads(urllib.request.urlopen(BASE + "/state", timeout=10).read())
    except Exception as e:
        return {"_err": str(e)}

# ---- state accessors ----
def proj(s): return s["document"]["projects"][0]
def spine(s): return proj(s)["sequence"]["spine"]
def clips(s): return [e["clip"]["_0"] for e in spine(s) if "clip" in e]
def nclips(s): return len(clips(s))
def assetN(s): return len(s["document"]["assetLibrary"])
def clip(s, i):
    cs = clips(s)
    return cs[i] if 0 <= i < len(cs) else None
def secs(t): return t["value"]/t["timescale"]
def ui(s): return s["ui"]

def agent(instruction):
    cmd("agentSend", path=instruction)

def busy(s):
    return bool(s.get("agentBusy", False))

def wait_idle(timeout=70, poll=1.0):
    """等 agent 处理完(agentBusy=false)。"""
    t0 = time.time()
    while time.time() - t0 < timeout:
        if not busy(state()):
            return True
        time.sleep(poll)
    return False

def wait_for(pred, timeout=70, poll=1.0):
    """先等 agent 空闲,再判断 pred;返回 (ok, finalState)。"""
    wait_idle(timeout)
    t0 = time.time()
    last = None
    while time.time() - t0 < 8:   # 空闲后再宽限几秒让状态落定
        s = state()
        last = s
        try:
            if pred(s):
                return True, s
        except Exception:
            pass
        time.sleep(poll)
    return False, last

# ---- 测试步骤:(标签, 指令, 断言) ----
# 顺序讲究:先 append 视频做 clip0,再跑【不改结构的画面/音频调整】(clip0 始终是视频,索引稳定),
# 最后才做会改片段数/顺序的结构操作,避免 clip0 漂移成音频导致"画面"操作被 agent 正确拒绝。
STEPS = [
    ("import 视频", f"导入这个视频文件 {VIDEO}", lambda s: assetN(s) >= 1),
    ("import 音乐", f"再导入这首音乐 {MUSIC}", lambda s: assetN(s) >= 2),
    ("append 视频", "把素材库第0个视频素材加到时间线末尾", lambda s: nclips(s) == 1),
    # --- 画面/音频调整(clip0=视频,结构不变) ---
    ("scale", "把主轴第0段画面放大到2倍", lambda s: abs(clip(s,0)["adjust"]["transform"]["scaleWidth"] - 2) < 0.01),
    ("crop", "把主轴第0段左边裁掉15%", lambda s: clip(s,0)["adjust"]["crop"]["left"] > 1),
    ("opacity", "把主轴第0段设成半透明", lambda s: clip(s,0)["adjust"]["opacity"] < 0.95),
    ("volume", "把主轴第0段的音量压到20%", lambda s: clip(s,0)["adjust"]["volume"] < 0.5),
    ("position", "把主轴第0段画面向右移动100像素", lambda s: clip(s,0)["adjust"]["transform"]["positionX"] > 50),
    ("add_effect", "给主轴第0段加高斯模糊特效", lambda s: any(fx.get("kind") == "blur" for fx in clip(s,0).get("effects", []))),
    ("add_keyframe", "给主轴第0段在第2秒加一个画面放大到1.5倍的变换关键帧", lambda s: len(clip(s,0).get("transformKeyframes", [])) >= 1),
    # --- 结构操作 ---
    ("append 音乐", "把素材库第1个音乐素材也加到时间线末尾", lambda s: nclips(s) == 2),
    ("connect", "把素材0叠加到3秒处的上一层轨道", lambda s: any(e.get("clip", {}).get("_0", {}).get("connected") for e in spine(s))),
    ("blade", "在主轴第0段的2秒处切一刀", lambda s: nclips(s) >= 3),
    ("transition", "在主轴第1段和它前面那段之间加1秒交叉叠化转场", lambda s: clip(s,1).get("crossfadeIn", {"value":0,"timescale":1})["value"] > 0),
    ("duplicate", "把主轴第0段复制一份粘贴到时间线末尾", lambda s: nclips(s) >= 4),
    # --- 导航 ---
    ("playhead", "把播放头跳到3秒", lambda s: abs(secs(ui(s)["playhead"]) - 3) < 0.2),
    ("zoom", "把时间线缩放设成每秒120像素", lambda s: abs(ui(s)["pxPerSecond"] - 120) < 1),
    ("tool", "切换到切割工具", lambda s: ui(s)["currentTool"] == "blade"),
    ("select", "选中主轴第0段", lambda s: ui(s).get("selectedClipID") is not None),
]

def main():
    results = []
    # 干净起点:建项目
    cmd("createProject", path="E2E", width=1920, seconds=1080)
    time.sleep(0.5)
    for label, instr, pred in STEPS:
        agent(instr)
        time.sleep(1.5)   # 让 agentBusy 先起来,避免空闲判定过早返回
        ok, s = wait_for(pred)
        results.append((label, ok))
        snap = ""
        if not ok:
            try: snap = f"  (clips={nclips(s)} assets={assetN(s)})"
            except Exception: snap = "  (state err)"
        print(f"{'✅' if ok else '❌'} {label}{snap}", flush=True)
    npass = sum(1 for _, ok in results if ok)
    print(f"\n=== T7 step A: {npass}/{len(results)} passed ===", flush=True)

if __name__ == "__main__":
    main()
