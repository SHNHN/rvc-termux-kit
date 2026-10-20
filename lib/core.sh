#!/usr/bin/env bash
# ============================================================
#  RVC Termux Kit - 公共函数库
#
#  被 scripts/ 下所有脚本 source。不要直接执行。
#  设计原则：
#    · 不硬编码任何绝对路径，一切相对 $ROOT
#    · 不假设在 Termux 里（Linux/macOS 也能跑）
#    · 生成的中间文件集中在 .work/，方便一键清理
# ============================================================

# ---- 定位项目根目录（本文件在 <root>/lib/core.sh）----
# 支持被 source，也支持被符号链接调用
_this="${BASH_SOURCE[0]:-$0}"
_root="$(cd "$(dirname "$_this")/.." && pwd -P)"
ROOT="${ROOT:-$_root}"
export ROOT

# ---- 目录约定 ----
CONFIG="$ROOT/config/config.ini"
INBOX="$ROOT/inbox"
DONE="$ROOT/done"
OUTBOX="$ROOT/out"
WORK="$ROOT/.work"
LOGS="$WORK/logs"
TMPD="$WORK/tmp"
STATE="$WORK/state"
ENGINE="$ROOT/engine"
MODELS="$ROOT/models"

ensure_dirs() {
  mkdir -p "$INBOX" "$DONE" "$OUTBOX" "$LOGS" "$TMPD" "$STATE" "$MODELS" 2>/dev/null
}

# ---- 配置读取 ----
# cfg <key> [default]
cfg() {
  local key="$1" def="${2:-}" val=""
  if [ -f "$CONFIG" ]; then
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG" 2>/dev/null \
          | tail -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]*#.*$//')
  fi
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$def"
}

# cfg_bool <key> [default]  -> 输出 1/0
cfg_bool() {
  local v; v=$(cfg "$1" "$2")
  case "$(printf '%s' "$v" | tr 'A-Z' 'a-z')" in
    yes|y|true|1|on)  echo 1 ;;
    *)                echo 0 ;;
  esac
}

# 一次读出转换参数，避免每处重复 cfg
load_settings() {
  PITCH=$(cfg pitch 0)
  SPEAKER=$(cfg speaker 0)
  EQ=$(cfg eq 5)
  EXTRA=$(cfg extra 3)
  THREADS=$(cfg threads 4)
  CHUNK=$(cfg chunk 4)
  PAD=$(cfg pad 1.0)
  F0_METHOD=$(cfg f0_method rmvpe)
  MODEL_NAME=$(cfg model mymodel.pth)
  AUTO_EQ=$(cfg_bool auto_eq yes)
  ARCHIVE_SRC=$(cfg_bool archive_source yes)
  OUT_FMT=$(cfg output_format wav)

  # 合法性兜底：配置写错也不该让脚本崩
  case "$PITCH"     in ''|*[!0-9-]*) PITCH=0 ;; esac
  case "$SPEAKER"   in ''|*[!0-9]*)  SPEAKER=0 ;; esac
  case "$EQ"        in ''|*[!0-9.]*) EQ=5 ;; esac
  case "$EXTRA"     in ''|*[!0-9.-]*) EXTRA=3 ;; esac
  case "$THREADS"   in ''|*[!0-9]*)  THREADS=4 ;; esac
  case "$CHUNK"     in ''|*[!0-9.]*) CHUNK=4 ;; esac
  case "$PAD"       in ''|*[!0-9.]*) PAD=1.0 ;; esac
  case "$F0_METHOD" in rmvpe|pm) ;; *) F0_METHOD=rmvpe ;; esac
  case "$OUT_FMT"   in wav|mp3) ;; *) OUT_FMT=wav ;; esac
}

# ---- Python 检测 ----
# 优先级：环境变量 → config.ini 的 python= → Termux 自带 → PATH
detect_python() {
  local c and_
  if [ -n "${RVC_PYTHON:-}" ] && [ -x "${RVC_PYTHON:-}" ]; then
    printf '%s' "$RVC_PYTHON"; return 0
  fi
  c=$(cfg python "")
  if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  # Termux 标准位置（不写死 app 包名，只用前缀）
  if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/python3" ]; then
    printf '%s' "$PREFIX/bin/python3"; return 0
  fi
  if [ -x "/data/data/com.termux/files/usr/bin/python3" ]; then
    printf '%s' "/data/data/com.termux/files/usr/bin/python3"; return 0
  fi
  command -v python3 2>/dev/null && return 0
  command -v python 2>/dev/null && return 0
  return 1
}

PY="$(detect_python)" || PY=""
need_python() {
  if [ -z "$PY" ] || [ ! -x "$PY" ]; then
    die "找不到 python3。先跑：bash scripts/install.sh"
  fi
  if ! "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
    die "Python 版本太老（需要 >= 3.10）。当前：$("$PY" -V 2>&1)"
  fi
}

# ---- 外部工具 ----
detect_ffmpeg() {
  if [ -x "${PREFIX:-}/bin/ffmpeg" ]; then printf '%s' "$PREFIX/bin/ffmpeg"; return 0; fi
  command -v ffmpeg 2>/dev/null && return 0
  return 1
}
FFMPEG="$(detect_ffmpeg)" || FFMPEG=""
need_ffmpeg() {
  [ -n "$FFMPEG" ] && [ -x "$FFMPEG" ] || die "找不到 ffmpeg。先跑：bash scripts/install.sh"
}
have_ffmpeg() { [ -n "$FFMPEG" ] && [ -x "$FFMPEG" ]; }

ffprobe_bin() {
  local d; d="$(dirname "$FFMPEG" 2>/dev/null)"
  if [ -x "$d/ffprobe" ]; then printf '%s' "$d/ffprobe"; else command -v ffprobe 2>/dev/null; fi
}

# ---- 输出 ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'
  C_B=$'\033[36m'; C_D=$'\033[90m'; C_0=$'\033[0m'
else
  C_R=''; C_G=''; C_Y=''; C_B=''; C_D=''; C_0=''
fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s⚠%s %s\n' "$C_Y" "$C_0" "$*"; }
err()  { printf '%s✗%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s\n' "──────────────────────────────────────────"; }

# ---- 时间 ----
fmt_dur() {
  local s=${1:-0}
  if [ "$s" -lt 60 ]; then printf '%d秒' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%d分%02d秒' $((s/60)) $((s%60))
  else printf '%d时%02d分' $((s/3600)) $(((s%3600)/60)); fi
}

# ---- 进程 ----
# 收集自己和所有祖先进程的 pid，用来排除
_self_chain() {
  local p=$$ out=" "
  while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ]; do
    out="$out$p "
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) break ;; esac
  done
  printf '%s' "$out"
}

# 扫 /proc 找命令行含某关键词的进程
# 关键：必须排除自己和祖先，否则 "--stop" 会把自己杀掉
find_pids() {
  local kw="$1" q c
  [ -d /proc ] || return 0
  local chain; chain=$(_self_chain)
  for q in /proc/[0-9]*; do
    q=${q#/proc/}
    case "$chain" in *" $q "*) continue ;; esac
    [ -r "/proc/$q/cmdline" ] || continue
    c=$(tr '\0' ' ' < "/proc/$q/cmdline" 2>/dev/null)
    [ -z "$c" ] && c=$(cat "/proc/$q/comm" 2>/dev/null)
    case "$c" in *"$kw"*) printf '%s\n' "$q" ;; esac
  done
}

pid_alive() {
  local p="$1"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null
}

# ---- 文件类型 ----
is_audio() {
  case "$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z')" in
    wav|mp3|flac|m4a|aac|ogg|opus|wma|aiff|aif) return 0 ;;
  esac
  return 1
}

# ---- 锁：防并发转换 ----
# 锁目录里放持有者 pid。持有者死了 → 自动清理，不会卡死后续任务。
LOCKD="$STATE/.convert.lock"
LOCKF="$STATE/.convert.pid"

lock_acquire() {
  if [ -d "$LOCKD" ]; then
    local p=""
    [ -f "$LOCKF" ] && p=$(cat "$LOCKF" 2>/dev/null)
    if pid_alive "$p"; then
      return 1
    fi
    # 持有者已消失：可能是被强杀留下的残留锁
    rmdir "$LOCKD" 2>/dev/null || rm -rf "$LOCKD" 2>/dev/null
    rm -f "$LOCKF"
  fi
  mkdir -p "$LOCKD" 2>/dev/null || return 1
  printf '%s' "$$" > "$LOCKF"
  LOCK_HELD=1
  return 0
}

lock_release() {
  [ "${LOCK_HELD:-0}" = "1" ] || return 0
  rm -f "$LOCKF" 2>/dev/null
  rmdir "$LOCKD" 2>/dev/null || rm -rf "$LOCKD" 2>/dev/null
  LOCK_HELD=0
}

lock_owner() {
  [ -f "$LOCKF" ] && cat "$LOCKF" 2>/dev/null
}

# ---- 内存检测：给出建议 chunk ----
detect_mem_gb() {
  local kb=0
  if [ -r /proc/meminfo ]; then
    kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
  fi
  [ -z "$kb" ] && { echo 0; return; }
  echo $(( kb / 1024 / 1024 ))
}

suggest_chunk() {
  local gb; gb=$(detect_mem_gb)
  if   [ "$gb" -le 0 ]; then echo 4
  elif [ "$gb" -lt 4 ]; then echo 3
  elif [ "$gb" -lt 7 ]; then echo 4
  else echo 8; fi
}

# ---- 模型解析 ----
resolve_model() {
  local m="$MODEL_NAME"
  case "$m" in
    /*) [ -f "$m" ] && { printf '%s' "$m"; return 0; } ;;
    *)  [ -f "$MODELS/$m" ] && { printf '%s' "$MODELS/$m"; return 0; } ;;
  esac
  # 兜底：models/ 里只有一个 .pth 就自动用它
  local n first
  n=$(find "$MODELS" -maxdepth 1 -name '*.pth' 2>/dev/null | wc -l)
  if [ "$n" = "1" ]; then
    first=$(find "$MODELS" -maxdepth 1 -name '*.pth' 2>/dev/null | head -1)
    [ -f "$first" ] && { printf '%s' "$first"; return 0; }
  fi
  return 1
}
