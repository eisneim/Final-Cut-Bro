#!/usr/bin/env python3
"""file_ops 工具 + 确认卡片 端到端测试(真实 LLM)。
测 3 件事:
1. read_file:让 agent 读一个已知文件,验证它能读到内容并回答
2. write_file:让 agent 写文件 → 出现确认卡片 → 我们模拟"允许" → 文件真的写入
3. write_file 拒绝:再让 agent 写 → 模拟"拒绝" → 文件不写入
server 由用户启动/关闭,本脚本不开关 server。"""
import json, time, urllib.request, os

BASE = "http://127.0.0.1:8765"
READ_SRC = "/tmp/fcpxbro_e2e_read.txt"
WRITE_DST = "/tmp/fcpxbro_e2e_write.txt"
REJECT_DST = "/tmp/fcpxbro_e2e_reject.txt"

def cmd(op, **kw):
    body = json.dumps({"op": op, **kw}).encode()
    req = urllib.request.Request(BASE + "/cmd", data=body, headers={"Content-Type": "application/json"})
    try: return urllib.request.urlopen(req, timeout=120).read()
    except Exception as e: return str(e).encode()
def agent():
    try: return json.loads(urllib.request.urlopen(BASE + "/agent", timeout=10).read())
    except Exception as e: return {"_err": str(e)}
def busy(): return bool(agent().get("busy", False))
def pending(): return bool(agent().get("pendingConfirm", False))

def wait(cond, timeout=180, poll=2):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if cond(): return True
        time.sleep(poll)
    return False

def last_texts(n=4):
    return [f"[{m['role']}] {m['text'][:80]}" for m in agent().get("messages", [])[-n:]]

def test_read():
    print("\n=== 测试 1: read_file ===", flush=True)
    with open(READ_SRC, "w") as f:
        f.write("秘密口令是 紫色大象42。这是测试文件。")
    cmd("agentSend", path=f"请用 read_file 读取文件 {READ_SRC} 并告诉我里面的秘密口令是什么")
    time.sleep(3)
    wait(lambda: not busy(), 180)
    time.sleep(1)
    msgs = agent().get("messages", [])
    full = " ".join(m["text"] for m in msgs)
    ok = "紫色大象42" in full
    print(f"  agent 读到口令: {'✅' if ok else '❌'}", flush=True)
    for t in last_texts(3): print("   ", t, flush=True)
    return ok

def test_write_approve():
    print("\n=== 测试 2: write_file + 允许 ===", flush=True)
    if os.path.exists(WRITE_DST): os.remove(WRITE_DST)
    cmd("agentSend", path=f"请用 write_file 在 {WRITE_DST} 写入一句话:今天天气很好")
    time.sleep(3)
    # 等确认卡片出现
    got_confirm = wait(pending, 120)
    print(f"  确认卡片出现: {'✅' if got_confirm else '❌'}", flush=True)
    if got_confirm:
        print(f"    卡片内容: {agent().get('confirmMessage','')[:80]}", flush=True)
        # 写入前文件不应存在
        print(f"  确认前文件未写入: {'✅' if not os.path.exists(WRITE_DST) else '❌'}", flush=True)
        cmd("respondConfirm", seconds=1)  # 允许
        wait(lambda: not busy(), 120)
        time.sleep(1)
    written = os.path.exists(WRITE_DST)
    content_ok = written and "今天天气很好" in open(WRITE_DST).read()
    print(f"  允许后文件写入且内容正确: {'✅' if content_ok else '❌'}", flush=True)
    for t in last_texts(3): print("   ", t, flush=True)
    return got_confirm and content_ok

def test_write_reject():
    print("\n=== 测试 3: write_file + 拒绝 ===", flush=True)
    if os.path.exists(REJECT_DST): os.remove(REJECT_DST)
    cmd("agentSend", path=f"请用 write_file 在 {REJECT_DST} 写入:不该出现的内容")
    time.sleep(3)
    got_confirm = wait(pending, 120)
    print(f"  确认卡片出现: {'✅' if got_confirm else '❌'}", flush=True)
    if got_confirm:
        cmd("respondConfirm", seconds=0)  # 拒绝
        wait(lambda: not busy(), 120)
        time.sleep(1)
    not_written = not os.path.exists(REJECT_DST)
    print(f"  拒绝后文件未写入: {'✅' if not_written else '❌'}", flush=True)
    for t in last_texts(3): print("   ", t, flush=True)
    return got_confirm and not_written

def main():
    st = agent()
    if "_err" in st:
        print("❌ server 未启动 —— 请先 bash scripts/run.sh"); return
    r1 = test_read()
    r2 = test_write_approve()
    r3 = test_write_reject()
    print("\n== 汇总 ==", flush=True)
    print(f"  read_file:        {'PASS' if r1 else 'FAIL'}", flush=True)
    print(f"  write+允许:       {'PASS' if r2 else 'FAIL'}", flush=True)
    print(f"  write+拒绝:       {'PASS' if r3 else 'FAIL'}", flush=True)
    for p in (READ_SRC, WRITE_DST, REJECT_DST):
        if os.path.exists(p): os.remove(p)

if __name__ == "__main__":
    main()
