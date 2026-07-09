#!/usr/bin/env python3
"""多素材/多镜头【剪废话+字幕】端到端 —— 一个目录里的 N 段口播视频(实拍常是多段),
按【文件名排序】(时间在前的在前)导入,读各自旁边的 <video>.asr.json(local-asr 产物),
拼一份带【素材分组表头】的 transcript 喂给内置 Agent。Agent 逐素材规划保留句、
【一次】build_subtitle_cut(每段带 assetIndex 指明来源)拼成一条连贯成片并导出。

server 由用户外部启动(bash scripts/run.sh),本脚本只驱动 :8765 + 验证,不自启不关闭。

用法:
    python3 scripts/subtitle_multi_e2e.py <视频目录> [--out 成片.mp4] [--width W --height H] [--fontsize 64 --y 480]
先决条件:目录里每个视频旁已有 <video>.asr.json(用 /local-asr 的 transcribe.py 生成)。
"""
import json, time, urllib.request, os, sys, glob, argparse

BASE = "http://127.0.0.1:8765"
VIDEO_EXTS = (".mp4", ".mov", ".m4v", ".MP4", ".MOV", ".M4V")

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
def wait_idle(timeout=600):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if not busy(): return True
        time.sleep(5)
    return False
def wait_export(timeout=600):
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

def find_videos(d):
    files = [f for f in glob.glob(os.path.join(d, "*")) if f.endswith(VIDEO_EXTS)]
    return sorted(files, key=lambda p: os.path.basename(p))   # 文件名排序 = 时间先后

def transcript_for(video):
    """读 <video>.asr.json,返回逐句 transcript 文本(无则返回 None)。"""
    j = os.path.splitext(video)[0] + ".asr.json"
    if not os.path.exists(j):
        # 有的命名是 video.mp4.asr.json
        alt = video + ".asr.json"
        if os.path.exists(alt): j = alt
        else: return None
    try:
        data = json.load(open(j, encoding="utf-8"))
    except Exception:
        return None
    lines = []
    for s in data.get("sentences", []):
        lines.append(f"[{s.get('index')}] {s.get('start'):.2f}-{s.get('end'):.2f} {s.get('text','')}")
    return "\n".join(lines)

def build_instruction(videos, out_path, fontsize, y):
    parts = ["这是【多段】未剪辑口播视频,每段是一个独立素材。按文件名排序(时间在前的是前面的句子)。\n"
             "各素材及其字幕(每行: 序号 起始秒-结束秒 文字):\n"]
    for i, v in enumerate(videos):
        t = transcript_for(v) or "(无字幕数据)"
        parts.append(f"\n【素材{i}: {os.path.basename(v)}】\n{t}\n")
    parts.append(
        "\n任务:把这几段【拼成一条连贯的干净成片】——去掉卡顿/口误/重拍/思考废话/重复的句子,只留说得完整的,"
        "按【素材0→素材1→…】的顺序衔接,并给每段配屏幕下方字幕。\n\n"
        "【只用一次 build_subtitle_cut 完成,不要逐段 append】:\n"
        "1) 先调 list_assets 确认每个文件对应的 assetIndex(应与上面素材编号一致)。\n"
        "2) 逐素材看字幕规划【保留句】(丢口误/重拍/没说完的错句/纯思考废话/和别的句子重复的)。\n"
        "3) 把保留段【一次性】传给 build_subtitle_cut:segments=[{from,to,text,assetIndex},...],"
        "按成片顺序排列,每段的【from/to 是它在其所属源视频里的时间】,assetIndex 指明它来自哪个素材。\n"
        f"   参数:fontSize={fontsize}, y={y}, exportPath=\"{out_path}\"。\n"
        "相邻且连续的句子可合并为一段(from 取前句起点、to 取后句终点、text 拼接)。一步到位。"
    )
    return "".join(parts)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", help="含多段视频 + 各自 .asr.json 的目录")
    ap.add_argument("--out", default=None, help="成片输出路径(默认 <dir>/_multi_edited.mp4)")
    ap.add_argument("--width", type=int, default=None, help="项目宽(默认取第一个素材)")
    ap.add_argument("--height", type=int, default=None, help="项目高(默认取第一个素材)")
    ap.add_argument("--fontsize", type=int, default=64)
    ap.add_argument("--y", type=int, default=480)
    args = ap.parse_args()

    videos = find_videos(args.dir)
    if not videos:
        print(f"❌ {args.dir} 里没找到视频"); return
    out_path = args.out or os.path.join(args.dir, "_multi_edited.mp4")
    if os.path.exists(out_path): os.remove(out_path)

    if "_err" in agent():
        print("❌ server 未启动,请先在另一个终端: bash scripts/run.sh"); return

    print(f">> 找到 {len(videos)} 段视频(按文件名排序):", flush=True)
    for i, v in enumerate(videos):
        has = "有字幕" if transcript_for(v) else "⚠无 .asr.json"
        print(f"   [{i}] {os.path.basename(v)}  ({has})", flush=True)

    print(">> 依次导入...", flush=True)
    for v in videos:
        cmd("importFile", path=v); time.sleep(0.8)
    time.sleep(1.0)

    # 项目尺寸:优先命令行,否则取第一个素材的自然尺寸
    s = state()
    assets = s.get("document", {}).get("assetLibrary", [])
    w, h = args.width, args.height
    if (w is None or h is None) and assets:
        a0 = assets[0]
        # Asset Codable 把尺寸摊成 naturalSizeWidth/Height 扁平 key
        w = w or int(a0.get("naturalSizeWidth", 1080))
        h = h or int(a0.get("naturalSizeHeight", 1920))
    w = w or 1080; h = h or 1920
    print(f">> 建项目 {w}×{h}(继承首个素材尺寸)...", flush=True)
    cmd("createProject", path="多素材剪辑", width=w, seconds=h)
    time.sleep(1.0)

    print(">> 发送任务(真实 LLM:list_assets → 规划保留段 → 一次 build_subtitle_cut → 导出)...", flush=True)
    cmd("agentSend", path=build_instruction(videos, out_path, args.fontsize, args.y))
    time.sleep(4)
    wait_idle(600)
    print(">> agent 空闲,等导出渲染...", flush=True)
    wait_export(600)

    s = state()
    vids = [c for c in spine_clips(s) if not c.get("title")]
    ts = all_titles(s)
    total = sum(c["duration"]["value"] / c["duration"]["timescale"] for c in vids) if vids else 0
    print("\n== 结果 ==", flush=True)
    print(f"主轴视频段数: {len(vids)}, 成片总时长 {total:.2f}s", flush=True)
    print(f"字幕条数: {len(ts)}", flush=True)
    for txt, _ in ts:
        print(f"   {txt}", flush=True)
    sz = os.path.getsize(out_path) if os.path.exists(out_path) else 0
    print(f"\n导出: {out_path} = {sz} bytes {'OK' if sz > 10000 else 'FAIL'}", flush=True)
    for m in agent().get("messages", [])[-2:]:
        if m["role"] == "assistant" and m["text"]:
            print(f"\nagent 总结: {m['text'][:280]}", flush=True)

if __name__ == "__main__":
    main()
