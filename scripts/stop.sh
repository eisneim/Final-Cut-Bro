#!/bin/bash
# 由【用户】关闭所有 FCPX-lite 实例 + 释放 8765 调试端口。
echo "关闭 FCPX-lite..."
pkill -9 -f 'FCPXLite' 2>/dev/null || true
sleep 0.3
if pgrep -fl FCPXLite >/dev/null 2>&1; then
  echo "仍有残留:"; pgrep -fl FCPXLite
else
  echo "已全部关闭。8765 端口: $(lsof -i :8765 2>/dev/null | wc -l | tr -d ' ') 个监听(应为 0)"
fi
