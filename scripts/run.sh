#!/bin/bash
# 由【用户】启动 FCPX-lite(debug 版含控制服务器,或 release 版)。
# 用法: bash scripts/run.sh          # debug(含 8765 自测服务器)
#       bash scripts/run.sh release  # release(不含服务器, 即给你日常用的)
set -euo pipefail
cd "$(dirname "$0")/.."

# 先确保没有旧实例残留
pkill -f '.build/.*/FCPXLite' 2>/dev/null || true
sleep 0.3

MODE="${1:-debug}"
if [ "$MODE" = "release" ]; then
  swift build -c release
  echo "启动 release 版(无调试服务器)..."
  exec ./.build/release/FCPXLite
else
  swift build
  echo "启动 debug 版(含 127.0.0.1:8765 调试服务器)..."
  echo "停止: 关窗口, 或另开终端跑 bash scripts/stop.sh"
  exec ./.build/debug/FCPXLite
fi
