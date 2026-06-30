#!/usr/bin/env python3
"""ASR→Agent剪辑→导出 端到端实验。把字幕+视频任务丢给 FCPX-lite agent,看它能否剪掉废话并导出。"""
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
        time.sleep(2)
    return False

def spine(s):
    try: return s["document"]["projects"][0]["sequence"]["spine"]
    except Exception: return []
def clips(s): return [e["clip"]["_0"] for e in spine(s) if "clip" in e]

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
    f"视频文件绝对路径: {VIDEO} ,总时长约 37.44 秒。\n"
    "这段视频里说话人有【口误重来】和【废话】。请你作为剪辑师:\n"
    "1) 新建一个 1920x1080 项目;\n"
    "2) 把这个视频导入并加到主时间线;\n"
    "3) 根据字幕判断哪些是口误/重来/思考废话(例如'等一下/这个说错了重新来'、'我认为这绝对是不对'这种没说完的、'呃/嗯让我想想'、'啊?差不多就这么'、以及把同一句话重复说的),"
    "用切割(blade)+删除(delete)把这些段落剪掉,只保留连贯正确的内容;\n"
    f"4) 最后把成片导出到 {OUT} 。\n"
    "注意:每次删除后片段序号会变,删之前先 query_timeline 看清楚。请一步步做完。"
)

def main():
    if os.path.exists(OUT): os.remove(OUT)
    print(">> 发送任务给 agent(真实 LLM,可能要几分钟)...", flush=True)
    cmd("agentSend", path=INSTRUCTION)
    time.sleep(3)
    wait_idle(360)
    # 导出是异步,再等产物
    for _ in range(40):
        if os.path.exists(OUT) and os.path.getsize(OUT) > 10000: break
        time.sleep(3)
    s = state()
    cs = clips(s)
    total = sum(c["duration"]["value"]/c["duration"]["timescale"] for c in cs)
    print(f"\n== 结果 ==", flush=True)
    print(f"时间线片段数: {len(cs)}, 总时长: {total:.2f}s (原始37.44s)", flush=True)
    for i, c in enumerate(cs):
        d = c["duration"]["value"]/c["duration"]["timescale"]
        si = c["sourceIn"]["value"]/c["sourceIn"]["timescale"]
        print(f"  clip{i}: sourceIn={si:.2f} dur={d:.2f} → 源[{si:.2f},{si+d:.2f}]", flush=True)
    sz = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    print(f"导出产物: {OUT} = {sz} bytes {'✅' if sz>10000 else '❌ 未生成'}", flush=True)

if __name__ == "__main__":
    main()
