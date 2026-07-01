#!/usr/bin/env python3
"""口播字幕剪辑端到端(720x1280 竖屏)。ASR 已转写(9 句,14.24s,干净口播)。
agent 只做语义判断(保留哪些句子),一次 build_subtitle_cut 完成提取+字幕+导出。
server 由脚本外部启动;本脚本只驱动 + 验证。"""
import json, time, urllib.request, os

BASE = "http://127.0.0.1:8765"
VIDEO = "/Users/teli/Downloads/subtitle_textMotion_caption2_20260518_140608_720x1280.mp4"
OUT = "/Users/teli/Downloads/subtitle_edited_720x1280.mp4"

def cmd(op, **kw):
    body = json.dumps({"op": op, **kw}).encode()
    req = urllib.request.Request(BASE + "/cmd", data=body, headers={"Content-Type": "application/json"})
    try: return json.loads(urllib.request.urlopen(req, timeout=120).read())
    except Exception as e: return {"_err": str(e)}
def state():
    try: return json.loads(urllib.request.urlopen(BASE + "/state", timeout=10).read())
    except Exception as e: return {"_err": str(e)}
def agent():
    try: return json.loads(urllib.request.urlopen(BASE + "/agent", timeout=10).read())
    except Exception as e: return {"_err": str(e)}
def busy(): return bool(state().get("agentBusy", False))
def export_progress(): return state().get("ui", {}).get("exportProgress")
def wait_idle(timeout=300):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if not busy(): return True
        time.sleep(5)
    return False
def wait_export(timeout=300):
    t0 = time.time(); started = False
    while time.time() - t0 < timeout:
        p = export_progress()
        if p is not None: started = True
        if started and p is None: return True
        time.sleep(3)
    return False
def spine_clips(s):
    try: return [e["clip"]["_0"] for e in s["document"]["projects"][0]["sequence"]["spine"] if "clip" in e]
    except Exception: return []
def all_titles(s):
    out = []
    for c in spine_clips(s):
        if c.get("title"): out.append((c["title"].get("text"), c))
        for ch in c.get("connected", []):
            if ch.get("title"):
                out.append((ch["title"].get("text"), ch))
    return out

# ASR 转写(干净口播,9 句,全保留)
TRANSCRIPT = """[0] 0.16-1.44 我认为人工智能绝对
[1] 1.44-2.88 是未来发展的方向
[2] 2.72-5.44 所以现在投入特别多的算力
[3] 5.20-8.00 特别多的人力呢，是完全值得的
[4] 7.84-9.36 我相信过了十年之后
[5] 9.20-10.48 你只要有很好的创意
[6] 10.40-12.40 你就可以做出非常牛逼的产品
[7] 12.32-12.64 所以
[8] 12.48-14.24 我们现在要赶紧开始学习AI"""

INSTRUCTION = (
    "这是一段说话视频的字幕(每行: 序号 起始秒-结束秒 文字):\n" + TRANSCRIPT + "\n\n"
    "视频已导入为素材库第0个,项目已建好(720x1280 竖屏)。\n"
    "任务:做一个【带字幕】的成片。这段口播很干净,没有明显口误/重拍,基本全保留。\n\n"
    "【只用一次 build_subtitle_cut 完成,不要逐段 append_clip/add_title】。\n"
    "1) 规划保留段:这段基本全保留。相邻且语义连续的句子可合并成一段字幕,让字幕更自然:\n"
    "   [0]+[1] 合成 '我认为人工智能绝对是未来发展的方向';[2]+[3] 合成一段;[7]'所以'很短可并入[8]。\n"
    "2) 一次性传给 build_subtitle_cut:segments=[{from:起始秒,to:结束秒,text:字幕},...](按时间先后),\n"
    "   assetIndex=0, fontSize=64, y=480(竖屏底部), exportPath=\"" + OUT + "\"。\n"
    "from/to 用合并后的时间范围(前句起点→后句终点),text 用拼接后的完整句子。"
)

def main():
    if os.path.exists(OUT): os.remove(OUT)
    if "_err" in agent():
        print("❌ server 未启动"); return
    print(">> 建项目(720x1280) + 导入视频...", flush=True)
    cmd("createProject", path="口播字幕", width=720, seconds=1280)
    cmd("importFile", path=VIDEO)
    time.sleep(1.5)
    print(">> 发送任务(真实 LLM)...", flush=True)
    cmd("agentSend", path=INSTRUCTION)
    time.sleep(4)
    wait_idle(300)
    print(">> agent 空闲,等导出渲染...", flush=True)
    wait_export(300)
    s = state()
    cs = spine_clips(s)
    vids = [c for c in cs if not c.get("title")]
    ts = all_titles(s)
    total = sum(c["duration"]["value"] / c["duration"]["timescale"] for c in vids)
    print("\n== 结果 ==", flush=True)
    print(f"主轴视频段数: {len(vids)}, 总时长 {total:.2f}s (原14.24s)", flush=True)
    print(f"字幕条数: {len(ts)}", flush=True)
    for txt, c in ts:
        off = c.get("offset", {})
        dur = c.get("duration", {})
        offs = off.get("value",0)/max(1,off.get("timescale",1))
        durs = dur.get("value",0)/max(1,dur.get("timescale",1))
        print(f"   [{offs:5.2f}s +{durs:4.2f}s] {txt}", flush=True)
    sz = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    print(f"\n导出: {OUT} = {sz} bytes {'OK' if sz > 10000 else 'FAIL'}", flush=True)
    # 最后一轮 agent 文本
    msgs = agent().get("messages", [])
    for m in msgs[-2:]:
        if m["role"] == "assistant" and m["text"]:
            print(f"\nagent: {m['text'][:200]}", flush=True)

if __name__ == "__main__":
    main()
