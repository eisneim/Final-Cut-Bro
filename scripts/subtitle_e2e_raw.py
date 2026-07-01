#!/usr/bin/env python3
"""口播【剪废话+字幕】端到端 —— 原始未剪辑视频 tstvideo_副本.mp4(720x1280,37.44s,含重拍/口误/废话)。
ASR 已转写(16 句,JSON 存在源文件旁)。agent 做语义判断(丢重拍/口误/废话/重复),
一次 build_subtitle_cut 完成 提取保留段+字幕+导出。server 外部启动,本脚本只驱动+验证。"""
import json, time, urllib.request, os

BASE = "http://127.0.0.1:8765"
VIDEO = "/Users/teli/Downloads/tstvideo_副本.mp4"
OUT = "/Users/teli/Downloads/tstvideo_副本_edited.mp4"

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
            if ch.get("title"): out.append((ch["title"].get("text"), ch))
    return out

TRANSCRIPT = """[0] 1.36-2.40 我认为人工智能
[1] 2.48-4.00 绝对是未来发展的方向
[2] 5.28-5.68 等一下
[3] 5.60-7.04 这个说错了，重新来一遍啊
[4] 7.92-10.00 我认为这绝对是不对
[5] 11.28-12.48 我认为人工智能绝
[6] 12.48-14.00 对是未来发展的方向
[7] 13.84-16.80 所以现在投入特别多的算力
[8] 16.64-19.20 特别多的人力呢，是完全值得的
[9] 19.12-20.40 我相信过了十年之后
[10] 20.96-22.80 呃，你只要有很好的创意
[11] 22.72-24.56 你就可以做出非常牛逼的产品
[12] 27.36-28.96 嗯，让我想想，还应该怎么说
[13] 31.12-31.68 啊？差不多就这么
[14] 32.72-34.72 所以，我们现在呢要赶紧学习
[15] 35.44-37.44 所以我们现在要赶紧开始学习AI"""

INSTRUCTION = (
    "这是一段【未剪辑】说话视频的字幕(每行: 序号 起始秒-结束秒 文字):\n" + TRANSCRIPT + "\n\n"
    "视频已导入为素材库第0个,项目已建好(720x1280 竖屏)。\n"
    "任务:做一个【剪掉废话/重拍/口误 + 带字幕】的干净成片。\n\n"
    "【只用一次 build_subtitle_cut 完成,不要逐段 append_clip/add_title】。\n"
    "1) 看字幕规划【保留】哪些句子。要丢:口误/重拍/没说完的错句/纯思考废话/和别的句子重复的(只留说得最完整的那一遍)。\n"
    "   参考:[2]'等一下'、[3]'说错了重新来'、[4]没说完的错句 → 丢;[0][1] 与 [5][6] 是同一句两遍,只留一遍;\n"
    "   [10] 开头'呃'、[12]'嗯让我想想'、[13]'啊?差不多' → 是废话;[14] 与 [15] 重复只留完整的 [15]。\n"
    "   字幕 text 可以写【干净版】(去掉'呃/嗯'这类语气词),但 from/to 用该句实际时间范围。\n"
    "2) 保留段【一次性】传给 build_subtitle_cut:segments=[{from:起始秒,to:结束秒,text:字幕},...](按时间先后),\n"
    "   assetIndex=0, fontSize=64, y=480(竖屏底部), exportPath=\"" + OUT + "\"。\n"
    "相邻且连续的句子可合并为一段(from 取前句起点、to 取后句终点、text 拼接)。一步到位。"
)

def main():
    if os.path.exists(OUT): os.remove(OUT)
    if "_err" in agent():
        print("❌ server 未启动"); return
    print(">> 建项目(720x1280) + 导入原始视频...", flush=True)
    cmd("createProject", path="口播剪辑", width=720, seconds=1280)
    cmd("importFile", path=VIDEO)
    time.sleep(1.5)
    print(">> 发送任务(真实 LLM,规划保留段→一次 build_subtitle_cut)...", flush=True)
    cmd("agentSend", path=INSTRUCTION)
    time.sleep(4)
    wait_idle(300)
    print(">> agent 空闲,等导出渲染...", flush=True)
    wait_export(300)
    s = state()
    vids = [c for c in spine_clips(s) if not c.get("title")]
    ts = all_titles(s)
    total = sum(c["duration"]["value"]/c["duration"]["timescale"] for c in vids)
    print("\n== 结果 ==", flush=True)
    print(f"主轴视频段数: {len(vids)}, 成片总时长 {total:.2f}s (原 37.44s)", flush=True)
    print(f"字幕条数: {len(ts)}", flush=True)
    acc = 0.0
    for txt, c in ts:
        print(f"   {txt}", flush=True)
    sz = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    print(f"\n导出: {OUT} = {sz} bytes {'OK' if sz > 10000 else 'FAIL'}", flush=True)
    for m in agent().get("messages", [])[-2:]:
        if m["role"] == "assistant" and m["text"]:
            print(f"\nagent 总结: {m['text'][:220]}", flush=True)

if __name__ == "__main__":
    main()
