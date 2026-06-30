#!/usr/bin/env python3
"""ASR→Agent剪辑(带字幕)实验 v2。策略:让 agent 先按时间戳规划保留段,再用 append_clip 批量提取+add_title 加字幕。
监控轻量:只 tail 日志(被动),低频(6s)查 agentBusy(/state 现已主线程外编码),不截图。"""
import json, time, urllib.request, os

BASE = "http://127.0.0.1:8765"
OUT = "/Users/teli/Downloads/tstvideo_edited.mp4"
VIDEO = "/Users/teli/Downloads/tstvideo_副本.mp4"

def cmd(op, **kw):
    body = json.dumps({"op": op, **kw}).encode()
    req = urllib.request.Request(BASE + "/cmd", data=body, headers={"Content-Type": "application/json"})
    try: return json.loads(urllib.request.urlopen(req, timeout=120).read())
    except Exception as e: return {"_err": str(e)}
def state():
    try: return json.loads(urllib.request.urlopen(BASE + "/state", timeout=10).read())
    except Exception as e: return {"_err": str(e)}
def busy(): return bool(state().get("agentBusy", False))
def wait_idle(timeout=360):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if not busy(): return True
        time.sleep(6)   # 低频,避免与流式抢主线程
    return False
def clips(s):
    try: return [e["clip"]["_0"] for e in s["document"]["projects"][0]["sequence"]["spine"] if "clip" in e]
    except Exception: return []
def titles(s):
    out = []
    try:
        for e in s["document"]["projects"][0]["sequence"]["spine"]:
            if "clip" not in e: continue
            c = e["clip"]["_0"]
            if c.get("title"): out.append(c["title"].get("text"))
            for ch in c.get("connected", []):
                if ch.get("title"): out.append(ch["title"].get("text"))
    except Exception: pass
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
    "这是一段说话视频的字幕(每行: 序号 起始秒-结束秒 文字):\n" + TRANSCRIPT + "\n\n"
    "视频已经导入为素材库第0个,项目也建好了(1920x1080)。\n"
    "任务:做一个【剪掉废话+带字幕】的成片。请按这个【策略】做:\n"
    "第一步【规划】:根据字幕判断要【保留】哪些句子、丢掉哪些。要丢的是口误/重来/思考废话——"
    "例如 [2][3] '等一下/这个说错了重新来'、[4] '我认为这绝对是不对'(没说完的错句)、[12] '嗯让我想想'、[13] '啊?差不多就这么'、"
    "以及和别的句子重复的(比如 [0][1] 和 [5][6] 是同一句的两遍,只留一遍;[14] 和 [15] 重复,只留 [15])。把保留的句子按时间先后列成一个计划。\n"
    "第二步【批量提取+加字幕】:对计划里的【每一个】保留句,依次做两件事:\n"
    "  (a) append_clip(assetIndex=0, fromSeconds=该句起始秒, toSeconds=该句结束秒) —— 把这句对应的视频片段提取拼到时间线;\n"
    "  (b) add_title(text=该句文字, duration=该句时长秒, fontSize=56, y=380) —— 给这句加屏幕下方字幕(atSeconds 省略就会落在刚追加片段的起点)。\n"
    "第三步【导出】:全部保留句处理完后,导出成片到 " + OUT + " 。\n"
    "注意:用 append_clip 批量提取,不要用 blade/delete(会算错时间)。一步步做完。"
)

def main():
    if os.path.exists(OUT): os.remove(OUT)
    cmd("createProject", path="ASR剪辑", width=1920, seconds=1080)
    cmd("importFile", path=VIDEO)
    time.sleep(1)
    print(">> 发送任务(真实 LLM,请耐心)...", flush=True)
    cmd("agentSend", path=INSTRUCTION)
    time.sleep(4)
    wait_idle(420)
    for _ in range(40):
        if os.path.exists(OUT) and os.path.getsize(OUT) > 10000: break
        time.sleep(4)
    s = state()
    cs = clips(s); ts = titles(s)
    total = sum(c["duration"]["value"]/c["duration"]["timescale"] for c in cs)
    print(f"\n== 结果 ==", flush=True)
    print(f"主轴片段(视频段)数: {len([c for c in cs if not c.get('title')])}, 总时长 {total:.2f}s (原37.44s)", flush=True)
    print(f"字幕条数: {len(ts)} -> {ts}", flush=True)
    sz = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    print(f"导出: {OUT} = {sz} bytes {'✅' if sz>10000 else '❌'}", flush=True)

if __name__ == "__main__":
    main()
