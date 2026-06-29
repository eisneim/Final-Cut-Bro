#!/usr/bin/env python3
"""T8 真实工作流(深度):一句话给 agent 多步指令,验证多步连贯 + 产物。
前置:由调用方启动 debug server(:8765)。本脚本预导入素材,发一条复合指令,验证末态 + 导出产物。
"""
import json, time, urllib.request, os

BASE = "http://127.0.0.1:8765"
VIDEO = "/Users/teli/Downloads/tstvideo_副本.mp4"
MUSIC = "/Users/teli/Downloads/_temp/音乐风格/Daya - Hide Away (Virtu Remix).mp3"
OUT = "/tmp/t8_export.mp4"

def cmd(op, **kw):
    body = json.dumps({"op": op, **kw}).encode()
    req = urllib.request.Request(BASE + "/cmd", data=body, headers={"Content-Type": "application/json"})
    try: return json.loads(urllib.request.urlopen(req, timeout=60).read())
    except Exception as e: return {"_err": str(e)}

def state():
    try: return json.loads(urllib.request.urlopen(BASE + "/state", timeout=10).read())
    except Exception as e: return {"_err": str(e)}

def spine(s): return s["document"]["projects"][0]["sequence"]["spine"]
def clips(s): return [e["clip"]["_0"] for e in spine(s) if "clip" in e]
def busy(s): return bool(s.get("agentBusy", False))

def wait_idle(timeout=180):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if not busy(state()): return True
        time.sleep(2)
    return False

def main():
    if os.path.exists(OUT): os.remove(OUT)
    cmd("createProject", path="T8", width=1920, seconds=1080)
    # 预导入素材(让 agent 专注剪辑工作流)
    cmd("importFile", path=VIDEO); time.sleep(0.5)
    cmd("importFile", path=MUSIC); time.sleep(0.5)

    instruction = (
        f"帮我做一个剪辑:第一步把素材库里的视频(第0个)加到主时间线;"
        f"第二步把音乐(第1个)作为背景音乐连接到时间线第0秒的上层轨道;"
        f"第三步把主轴视频那段的原声音量压低到20%(这样背景音乐更突出);"
        f"第四步把成片导出到 {OUT}。请依次完成。"
    )
    print("发送复合指令(真实 LLM 多步)...", flush=True)
    cmd("agentSend", path=instruction)
    time.sleep(2)
    wait_idle()
    # 导出是异步的,额外等产物落盘
    for _ in range(30):
        if os.path.exists(OUT) and os.path.getsize(OUT) > 10000: break
        time.sleep(2)

    s = state()
    cs = clips(s)
    # 断言
    has_main = len(cs) >= 1
    connected = any(c.get("connected") for c in cs)
    low_vol = any(c["adjust"]["volume"] < 0.5 for c in cs)
    exported = os.path.exists(OUT) and os.path.getsize(OUT) > 10000

    def mark(b): return "✅" if b else "❌"
    print(f"{mark(has_main)} 主轴有视频片段 (clips={len(cs)})", flush=True)
    print(f"{mark(connected)} 背景音乐已连接到上层", flush=True)
    print(f"{mark(low_vol)} 有片段原声被压低(<0.5)", flush=True)
    sz = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    print(f"{mark(exported)} 成片已导出 {OUT} ({sz} bytes)", flush=True)
    npass = sum([has_main, connected, low_vol, exported])
    print(f"\n=== T8 工作流: {npass}/4 ===", flush=True)

if __name__ == "__main__":
    main()
