#!/usr/bin/env python3
"""ASR→Agent 字幕剪辑实验 v3(程序化批量)。

关键改进 vs v2:不再让 agent 逐段 append_clip+add_title(几十次 LLM 往返、还夹杂 undo,极低效)。
现在 agent 只做【一件语义判断】——看字幕决定保留哪些句子(丢口误/重拍/思考废话/重复),
然后【一次】调用 build_subtitle_cut(segments=[全部保留段], exportPath=...),
由 Swift 在一个事务里批量:逐段提取源区间+加字幕+导出。一次工具调用完成全部机械工作。

监控轻量:被动 tail 日志 + 低频(6s)查 agentBusy,不截图、不在流式时抢主线程。
用完【必须】由用户关 server(本脚本不开关 server)。"""
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
def wait_idle(timeout=300):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if not busy(): return True
        time.sleep(6)
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
    "视频已导入为素材库第0个,项目已建好(1920x1080)。\n"
    "任务:做一个【剪掉废话+带字幕】的成片。\n\n"
    "【重要:只用一次 build_subtitle_cut 完成,不要逐段 append_clip/add_title】。步骤:\n"
    "1) 先看字幕规划【保留】哪些句子。要丢:口误/重拍/没说完的错句/纯思考废话/和别的句子重复的(只留说得最完整的那一遍)。\n"
    "   例如 [2][3] '等一下/这个说错了重新来'、[4] 没说完的错句、[12]'嗯让我想想'、[13]'啊?差不多就这么' 都丢;\n"
    "   [0][1] 和 [5][6] 是同一句两遍,只留更完整的 [5][6](可把相邻两行合成一段);[14] 与 [15] 重复只留 [15]。\n"
    "2) 把保留段【一次性】传给 build_subtitle_cut:segments=[{from:起始秒,to:结束秒,text:字幕},...](按时间先后),\n"
    "   assetIndex=0, fontSize=56, y=380, exportPath=\"" + OUT + "\"。\n"
    "相邻且连续的句子(如 [5]12.48 接 [6]起点)可合并为一段:from 取前句起点、to 取后句终点、text 拼接。一步到位。"
)

def main():
    if os.path.exists(OUT): os.remove(OUT)
    print(">> 建项目 + 导入视频...", flush=True)
    cmd("createProject", path="ASR剪辑", width=1920, seconds=1080)
    cmd("importFile", path=VIDEO)
    time.sleep(1)
    print(">> 发送任务(真实 LLM,只需一次工具调用,耐心等)...", flush=True)
    cmd("agentSend", path=INSTRUCTION)
    time.sleep(4)
    wait_idle(300)
    print(">> agent 空闲,等导出落盘...", flush=True)
    for _ in range(45):
        if os.path.exists(OUT) and os.path.getsize(OUT) > 10000: break
        time.sleep(4)
    s = state()
    cs = clips(s); ts = titles(s)
    vids = [c for c in cs if not c.get("title")]
    total = sum(c["duration"]["value"] / c["duration"]["timescale"] for c in vids)
    print("\n== 结果 ==", flush=True)
    print(f"主轴视频段数: {len(vids)}, 总时长 {total:.2f}s (原37.44s)", flush=True)
    print(f"字幕条数: {len(ts)} -> {ts}", flush=True)
    sz = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    print(f"导出: {OUT} = {sz} bytes {'OK' if sz > 10000 else 'FAIL'}", flush=True)

if __name__ == "__main__":
    main()
