#!/usr/bin/env bash
# ============================================================
#  watch.sh - 盯着 inbox/，有新音频就自动转换
#
#  用法：
#     ./watch.sh              前台运行（能看进度，Ctrl+C 退出）
#     ./watch.sh --daemon     放后台（日志在 .work/logs/watch.log）
#     ./watch.sh --stop       停掉后台的那个
#     ./watch.sh --status     看它活没活着
#
#  为什么单独做这个：让批处理能挂着跑，不用一直守着屏幕。
#  它由你启动、用你的 python，不会有跨 App 的权限问题。
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
load_settings

WATCH_LOG="$LOGS/watch.log"
WATCH_PID="$STATE/watch.pid"

# 只认"真正在跑循环的监听器"：
# 命令行里必须含 watch.sh 且不含 --stop/--status/--daemon/--help
# 否则 --stop 会把自己当成目标，--daemon 会误判"已在跑"
running_pids() {
  local q c
  local chain; chain=$(_self_chain)
  for q in /proc/[0-9]*; do
    q=${q#/proc/}
    case "$chain" in *" $q "*) continue ;; esac
    [ -r "/proc/$q/cmdline" ] || continue
    c=$(tr '\0' ' ' < "/proc/$q/cmdline" 2>/dev/null)
    case "$c" in
      *watch.sh*)
        case "$c" in
          *--stop*|*--status*|*--daemon*|*--help*|-s*) continue ;;
        esac
        printf '%s\n' "$q"
        ;;
    esac
  done
}

do_status() {
  local pids; pids=$(running_pids)
  if [ -n "$pids" ]; then
    printf '  监听中 ✓  pid: %s\n' "$(echo "$pids" | tr '\n' ' ')"
  else
    printf '  未运行\n'
  fi
  local n=0 f
  for f in "$INBOX"/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in .*) continue ;; esac
    is_audio "$f" && n=$((n+1))
  done
  printf '  待转换 %d 个\n' "$n"
}

do_stop() {
  local pids
  pids=$(running_pids)
  if [ -z "$pids" ]; then info "本来就没在运行"; return 0; fi
  for p in $pids; do
    [ "$p" = "$$" ] && continue
    kill "$p" 2>/dev/null
  done
  sleep 1
  for p in $pids; do
    [ "$p" = "$$" ] && continue
    pid_alive "$p" && kill -9 "$p" 2>/dev/null
  done
  rm -f "$WATCH_PID"
  ok "已停止监听"
}

# ---- 主循环 ----
run_loop() {
  need_python
  if ! "$PY" -c 'import torch' >/dev/null 2>&1; then
    die "这个 python 不能 import torch：$PY
请先跑：bash scripts/install.sh"
  fi

  hr
  say "  RVC Termux Kit 监听器"
  say "  python   : $PY"
  say "  监听目录 : ${INBOX#$ROOT/}/"
  say "  输出目录 : ${OUTBOX#$ROOT/}/"
  say "  模型     : $MODEL_NAME"
  say "  参数     : 变调 $PITCH | 说话人 $SPEAKER | 提亮 ${EQ}dB"
  say "  Ctrl+C 退出"
  hr

  local idle=0
  while true; do
    local found=0 f
    for f in "$INBOX"/*; do
      [ -e "$f" ] || continue
      case "${f##*/}" in .*|*.part|*.tmp) continue ;; esac
      is_audio "$f" || continue
      found=1
      printf '\n[%s] 发现 %s\n' "$(date '+%H:%M:%S')" "${f##*/}"
      bash "$ROOT/scripts/convert.sh" "$f"
      idle=0
    done
    if [ "$found" = 0 ]; then
      idle=$((idle+1))
      printf '\r等待新文件… %s   ' "$(date '+%H:%M:%S')"
    fi
    sleep 5
  done
}

case "${1:-}" in
  --status|-s) do_status ;;
  --stop)      do_stop ;;
  --daemon|-d)
    if [ -n "$(running_pids)" ]; then
      info "已经在跑了（pid $(running_pids | tr '\n' ' ')）"
      exit 0
    fi
    mkdir -p "$LOGS"
    : > "$WATCH_LOG"
    # nohup + setsid 双保险：脱离终端、忽略挂断、输出重定向到日志
    # 注意：某些 shell 里 `setsid cmd &` 会立刻返回但子进程没起来，
    # 所以启动后立刻校验，起不来就退回 nohup。
    if command -v setsid >/dev/null 2>&1; then
      setsid nohup bash "$ROOT/scripts/watch.sh" > "$WATCH_LOG" 2>&1 < /dev/null &
    else
      nohup bash "$ROOT/scripts/watch.sh" > "$WATCH_LOG" 2>&1 < /dev/null &
    fi
    echo $! > "$WATCH_PID"
    sleep 2
    if [ -z "$(running_pids)" ]; then
      warn "setsid 方式没起来，改用 nohup 重试"
      nohup bash "$ROOT/scripts/watch.sh" > "$WATCH_LOG" 2>&1 < /dev/null &
      echo $! > "$WATCH_PID"
      sleep 2
    fi
    sleep 1
    ok "已后台启动，pid $(cat "$WATCH_PID")"
    info "  日志：${WATCH_LOG#$ROOT/}"
    info "  停掉：./watch.sh --stop"
    ;;
  ""|--run)
    trap 'printf "\n"; ok "已退出监听"; exit 0' INT TERM
    run_loop
    ;;
  -h|--help)
    sed -n '2,16p' "$0" | sed 's/^#  \{0,2\}//'
    ;;
  *) die "未知选项：$1" ;;
esac
