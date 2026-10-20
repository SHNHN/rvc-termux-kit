#!/usr/bin/env bash
# ============================================================
#  doctor.sh - 环境自检 / 一键排错
#
#  用法：./doctor.sh
#
#  逐项检查并给出可以直接复制的修复命令。
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
load_settings

FAIL=0
pass() { printf '  %s✓%s %-22s %s\n' "$C_G" "$C_0" "$1" "${2:-}"; }
faild(){ printf '  %s✗%s %-22s %s\n' "$C_R" "$C_0" "$1" "${2:-}"; FAIL=$((FAIL+1)); }
warno(){ printf '  %s⚠%s %-22s %s\n' "$C_Y" "$C_0" "$1" "${2:-}"; }

hr
say "  RVC Termux Kit 自检"
say "  项目目录 $ROOT"
hr

# ---- 目录 ----
say "  目录"
for d in inbox done out models engine config; do
  if [ -d "$ROOT/$d" ]; then pass "$d/"
  else
    case "$d" in
      inbox|done|out|models) mkdir -p "$ROOT/$d" 2>/dev/null && pass "$d/ (已创建)" || faild "$d/";;
      engine) faild "engine/" "引擎源码不在，见 README「引擎准备」";;
      config) faild "config/" "配置目录不在";;
    esac
  fi
done

# ---- 引擎 ----
say ""
say "  引擎"
if [ -f "$ENGINE/cli.py" ]; then pass "cli.py"
else faild "cli.py" "从上游 RVC 项目获取，见 README"; fi

# ---- Python ----
say ""
say "  Python"
PY="$(detect_python)" || PY=""
if [ -z "$PY" ] || [ ! -x "$PY" ]; then
  faild "python3" "未安装 → bash scripts/install.sh"
else
  v=$("$PY" -V 2>&1 | cut -d' ' -f2)
  major=$("$PY" -c 'import sys;print(sys.version_info[0])' 2>/dev/null || echo 0)
  minor=$("$PY" -c 'import sys;print(sys.version_info[1])' 2>/dev/null || echo 0)
  if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; }; then
    pass "python $v" "$PY"
  else
    faild "python $v" "版本太低，需要 3.10+"
  fi

  # 逐模块导入测试（区分"没装"和"装了但加载失败"）
  for m in torch numpy scipy; do
    out=$("$PY" -c "import $m" 2>&1)
    if [ -z "$out" ]; then
      ver=$("$PY" -c "import $m;print(getattr($m,'__version__','?'))" 2>/dev/null)
      pass "$m" "$ver"
    elif echo "$out" | grep -q "ModuleNotFoundError\|No module named"; then
      faild "$m" "未安装 → bash scripts/install.sh --deps"
    elif echo "$out" | grep -q "cannot locate symbol"; then
      faild "$m" "动态库符号缺失 → pkg upgrade -y（升级 libc++）"
    else
      faild "$m" "$(echo "$out" | tail -1 | cut -c1-70)"
    fi
  done

  for m in typing_extensions filelock fsspec jinja2; do
    if "$PY" -c "import $m" >/dev/null 2>&1; then pass "$m"
    else faild "$m" "pip install --no-deps $m"; fi
  done
fi

# ---- ffmpeg ----
say ""
say "  外部工具"
FFMPEG="$(detect_ffmpeg)" || FFMPEG=""
if [ -n "$FFMPEG" ] && "$FFMPEG" -version >/dev/null 2>&1; then
  pass "ffmpeg" "$("$FFMPEG" -version 2>/dev/null | head -1 | cut -c1-45)"
elif [ -n "$FFMPEG" ]; then
  msg=$("$FFMPEG" -version 2>&1 | tail -1)
  if echo "$msg" | grep -q "cannot locate symbol"; then
    faild "ffmpeg" "动态库符号缺失 → pkg upgrade -y && pkg install -y ffmpeg"
  else
    faild "ffmpeg" "$(echo "$msg" | cut -c1-60)"
  fi
else
  faild "ffmpeg" "未安装 → pkg install -y ffmpeg"
fi

# ---- 模型 ----
say ""
say "  模型"
if m=$(resolve_model); then
  sz=$(stat -c%s "$m" 2>/dev/null || stat -f%z "$m" 2>/dev/null || echo 0)
  pass "模型" "$(basename "$m")  $(( sz / 1024 / 1024 )) MB"
else
  n=$(find "$MODELS" -maxdepth 1 -name '*.pth' 2>/dev/null | wc -l)
  if [ "$n" -gt 1 ]; then
    faild "模型" "models/ 里有 $n 个 .pth，请在 config.ini 的 model= 指定用哪个"
  else
    faild "模型" "models/ 里没有 .pth → 把你的模型放进去"
  fi
fi
idx=$(find "$MODELS" -maxdepth 1 -name '*.index' 2>/dev/null | head -1)
[ -n "$idx" ] && warno "索引文件" "$(basename "$idx") 需要 faiss，手机端不用管"

# ---- 参数合理性 ----
say ""
say "  参数"
memgb=$(detect_mem_gb)
say "  内存 $( [ "$memgb" -gt 0 ] && echo "$memgb GB" || echo 未知)"
awk -v c="$CHUNK" -v t="$THREADS" 'BEGIN{
  if (c+0 <= 0 || t+0 <= 0) { print "  !chunk/threads 必须是正数"; exit 1 }
}' || FAIL=$((FAIL+1))
if [ "$memgb" -gt 0 ]; then
  # 粗估：chunk 4 ≈ 2.7GB，按比例外推
  est=$(awk -v c="$CHUNK" 'BEGIN{printf "%.1f", c*0.68}')
  if awk -v e="$est" -v m="$memgb" 'BEGIN{exit !(e > m*0.75)}'; then
    warno "chunk=$CHUNK" "预计峰值 ~${est}GB，占内存 ${memgb}GB 的很大部分，建议降到 $(suggest_chunk)"
  else
    pass "chunk=$CHUNK" "预计峰值 ~${est}GB / ${memgb}GB"
  fi
fi
if [ "$THREADS" -gt 8 ]; then warno "threads=$THREADS" "超过 8 一般会因发热降频而变慢"; fi
cpu=$(nproc 2>/dev/null || echo 0)
[ "$cpu" -gt 0 ] && [ "$THREADS" -gt "$cpu" ] && warno "threads=$THREADS" "超过 CPU 核心数 $cpu"

# ---- 锁 ----
say ""
say "  运行状态"
owner=$(lock_owner)
if [ -d "$LOCKD" ]; then
  if pid_alive "$owner"; then
    pass "转换锁" "转换中，pid $owner"
  else
    warno "转换锁" "残留锁（持有者已退出），正在清理"
    rm -rf "$LOCKD"; rm -f "$LOCKF"
  fi
else
  pass "转换锁" "空闲"
fi
w=$(find_pids "watch.sh")
[ -n "$w" ] && pass "监听器" "运行中 pid $(echo $w | tr '\n' ' ')" || pass "监听器" "未运行"

# ---- 总结 ----
hr
if [ "$FAIL" -eq 0 ]; then
  ok "全部通过，可以开始转换了"
  say ""
  say "    ./rvc-kit convert <音频>"
  exit 0
else
  err "$FAIL 项有问题，按上面的提示修"
  exit 1
fi
