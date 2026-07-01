#!/usr/bin/env python3
"""GUI 性能对照实验:验证「Agent 流式输出让时间轴编辑卡顿」的根因(主线程争用)。

对照组设计(同一段真实编辑操作,跑两次):
  A. 控制组(baseline):Agent 空闲时,快速 burst 一串播放头移动(每次触发时间轴重画)。
  B. 处理组(treatment):先让 Agent 开始【真实流式输出】,在流式进行中跑【同样的】编辑 burst。
比较两组 PerfProbe 指标:
  - TimelineCanvas.updateNSView 的 count / avg / max(时间轴重画耗时)
  - DocumentStore.dispatch 的 count / avg
  - AgentService.tokenApply 的 count / total(流式在主线程上花了多少时间)
若两组 updateNSView 次数相近但 treatment 的编辑 wall-clock 明显变长、
且 tokenApply 在同期占用大量主线程时间 → 证实主线程争用(而非编辑本身变贵)。

server 由【用户】启动/关闭,本脚本只驱动,不开关 server。
用法:先造一条【多片段】时间轴(手动导入素材铺满,或用已有工程),再跑本脚本。
"""
import json, time, urllib.request

BASE = "http://127.0.0.1:8765"

def cmd(op, **kw):
    body = json.dumps({"op": op, **kw}).encode()
    req = urllib.request.Request(BASE + "/cmd", data=body, headers={"Content-Type": "application/json"})
    try: return urllib.request.urlopen(req, timeout=30).read()
    except Exception as e: return str(e).encode()

def get(path):
    try: return urllib.request.urlopen(BASE + path, timeout=10).read().decode()
    except Exception as e: return f"_ERR {e}"

def agent():
    try: return json.loads(urllib.request.urlopen(BASE + "/agent", timeout=10).read())
    except Exception as e: return {"_err": str(e)}

def state():
    try: return json.loads(urllib.request.urlopen(BASE + "/state", timeout=10).read())
    except Exception as e: return {"_err": str(e)}

def spine_clip_count():
    st = state()
    spine = st.get("document", {}).get("sequence", {}).get("spine", [])
    return sum(1 for e in spine if "clip" in e)

def edit_burst(n=80, span=20.0):
    """快速来回移动播放头 n 次,每次都会触发时间轴重画。返回 wall-clock 秒。"""
    t0 = time.time()
    for i in range(n):
        secs = (i % 40) / 40.0 * span   # 0..span 来回扫
        cmd("setPlayhead", seconds=secs)
    return time.time() - t0

def main():
    if "_err" in agent():
        print("❌ server 未启动 —— 请先 bash scripts/run.sh"); return
    nclips = spine_clip_count()
    print(f"当前时间轴片段数: {nclips}")
    if nclips < 10:
        print("⚠️  片段太少,卡顿不明显。建议先铺 ≥30 个片段(导入素材多次插入)再测。")

    # ---------- A. 控制组:agent 空闲 ----------
    print("\n===== A. 控制组(agent 空闲)=====")
    cmd("perfEnable", seconds=1)
    cmd("perfReset")
    wall_a = edit_burst()
    time.sleep(0.5)   # 让 SwiftUI runloop 把重画跑完
    report_a = get("/perf")
    print(f"编辑 burst wall-clock: {wall_a*1000:.0f} ms")
    print(report_a)

    # ---------- B. 处理组:agent 流式输出中 ----------
    print("\n===== B. 处理组(agent 流式输出进行中)=====")
    cmd("perfReset")
    # 让 agent 产生【长】输出(不必真剪,只要持续 streaming 占主线程)
    cmd("agentSend", path="请详细地、分步骤地、用很长的篇幅解释视频剪辑里"
                          "磁性时间线、连接片段、字幕轨道的工作原理,越详细越好。")
    time.sleep(1.5)   # 等流式真正开始吐 token
    busy_at_start = agent().get("busy", False)
    print(f"burst 开始时 agent busy = {busy_at_start}")
    wall_b = edit_burst()
    time.sleep(0.5)
    report_b = get("/perf")
    print(f"编辑 burst wall-clock: {wall_b*1000:.0f} ms")
    print(report_b)
    cmd("agentStop")

    # ---------- 结论 ----------
    print("\n===== 对照结论 =====")
    print(f"编辑 burst wall-clock:  A(空闲)={wall_a*1000:.0f}ms   B(流式中)={wall_b*1000:.0f}ms"
          f"   → 变慢 {(wall_b/wall_a - 1)*100:.0f}%" if wall_a > 0 else "")
    print("看上面两张 /perf 表:")
    print(" - 若 B 的 updateNSView.avg/max 明显 > A,或 tokenApply.total 很大 → 主线程争用确诊。")
    print(" - 若 B 的 updateNSView.count 反而暴涨 → streaming 意外触发了时间轴失效(另一种 bug)。")

if __name__ == "__main__":
    main()
