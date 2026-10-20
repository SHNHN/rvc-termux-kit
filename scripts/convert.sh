#!/usr/bin/env bash
# ============================================================
#  convert.sh - 单个/批量音频转换为目标音色
#
#  用法：
#     ./convert.sh <文件...>              转换指定文件
#     ./convert.sh --all                  inbox/ 下全部
#     ./convert.sh --status               看当前状态与进度
#
#  输出落在 out/ 下，文件名 <原名>_<模型短名>.wav
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
load_settings

# ---------- 进度显示 ----------
# 引擎会周期性打印：
#   [vc ] 分块 3/10 | 已用 12.4 分钟 | 还需 28.1 分钟
PROGRESS_FILE="$LOGS/.progress"

progress_parse() {
  local line n m used left pct filled bar i
  line=$(grep -a '分块 ' "$PROGRESS_FILE" 2>/dev/null | tail -1)
  [ -z "$line" ] && return 1
  if [[ $line =~ 分块[[:space:]]*([0-9]+)/([0-9]+)[^0-9]*([0-9.]+)[^0-9]*([0-9.]+) ]]; then
    n=${BASH_REMATCH[1]}; m=${BASH_REMATCH[2]}
    used=${BASH_REMATCH[3]}; left=${BASH_REMATCH[4]}
  elif [[ $line =~ ([0-9]+)/([0-9]+) ]]; then
    n=${BASH_REMATCH[1]}; m=${BASH_REMATCH[2]}; used=""; left=""
  else
    return 1
  fi
  [ "$m" -gt 0 ] 2>/dev/null || return 1
  pct=$(( n * 100 / m ))
  filled=$(( pct / 5 ))
  bar=""
  for ((i = 0; i < 20; i++)); do
    if [ "$i" -lt "$filled" ]; then bar="$bar█"; else bar="$bar░"; fi
  done
  printf '  分块进度  [%s] %d%%  (%s/%s)\n' "$bar" "$pct" "$n" "$m"
  [ -n "$used" ] && printf '  已用时间  %s 分钟\n' "$used"
  [ -n "$left" ] && printf '  预计还需  %s 分钟\n' "$left"
}

show_progress() {
  local owner; owner=$(lock_owner)
  if [ -d "$LOCKD" ] && pid_alive "$owner"; then
    printf '%s\n' "────────────── 转换中 ──────────────"
    if ! progress_parse; then
      # 还没进分块阶段：报一下已经跑了多久
      local t0 now
      t0=$(stat -c %Y "$PROGRESS_FILE" 2>/dev/null || stat -f %m "$PROGRESS_FILE" 2>/dev/null || echo 0)
      now=$(date +%s)
      printf '  正在加载模型 / 提取音高（已 %s）\n' "$(fmt_dur $(( now - t0 )))"
      printf '  分块进度还没开始，再等等\n'
    fi
    return 0
  fi
  return 1
}

# ---------- 状态 ----------
cmd_status() {
  local n
  say "════════ RVC Termux Kit ════════"
  printf '  模型      %s\n' "$MODEL_NAME"
  printf '  参数      变调 %s | 说话人 %s | 提亮 %sdB | 人声前推 %sdB\n' \
         "$PITCH" "$SPEAKER" "$EQ" "$EXTRA"
  printf '  性能      线程 %s | 分块 %ss | 重叠 %ss\n' "$THREADS" "$CHUNK" "$PAD"
  n=0
  for f in "$INBOX"/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in .*) continue ;; esac
    is_audio "$f" && n=$((n+1))
  done
  printf '  待转换    %d 个\n' "$n"
  printf '  已完成    %d 个\n' "$(find "$OUTBOX" -maxdepth 1 -name '*.wav' -o -maxdepth 1 -name '*.mp3' 2>/dev/null | wc -l)"
  if ! show_progress; then
    printf '  当前      空闲\n'
  fi
  say "════════════════════════════════"
}

# ---------- 转换单个 ----------
convert_one() {
  local src="$1"
  [ -f "$src" ] || { err "找不到文件：$src"; return 2; }
  is_audio "$src" || { err "不是音频文件：$src"; return 2; }

  local base name short model out
  base="${src##*/}"; name="${base%.*}"
  if [ -n "${MODEL_TAG:-}" ]; then short="$MODEL_TAG"; else
    short=$(basename "$MODEL_NAME" .pth); short="${short##*_}"
  fi
  out="$OUTBOX/${name}_${short}.${OUT_FMT}"

  if [ -f "$out" ]; then
    ok "已存在，跳过：${out##*/}"
    return 0
  fi

  if ! lock_acquire; then
    err "已有转换在跑（pid $(lock_owner)），等它完成；或 ./convert.sh --status 看进度"
    return 3
  fi
  trap 'lock_release' EXIT INT TERM

  model=$(resolve_model) || {
    lock_release
    err "找不到模型。请把 .pth 放进 models/，并在 config/config.ini 里设置 model="
    return 5
  }

  # 时长（估算 ETA 用）
  local dur="" PB
  PB=$(ffprobe_bin)
  if [ -n "$PB" ] && [ -x "$PB" ]; then
    dur=$("$PB" -v error -show_entries format=duration -of csv=p=0 "$src" 2>/dev/null | cut -d. -f1)
  fi

  hr
  say "  输入  $name"
  if [ -n "${dur:-}" ]; then
    local est=$(( dur * 22 ))
    say "  时长  ${dur} 秒    预计约 $(fmt_dur "$est")（实测速率，手机越热越慢）"
  fi
  say "  设置  变调 $PITCH | 说话人 $SPEAKER | 提亮 +${EQ}dB | 线程 $THREADS | 分块 ${CHUNK}s"
  hr

  : > "$PROGRESS_FILE"

  # ---- 调用引擎 ----
  # 每一层都要行缓冲，否则进度行会攒到最后才吐出来。
  # 引擎里的包用绝对 import（from infer.xxx），所以要在 engine/ 下运行；
  # hubert/rmvpe 权重统一从 models/ 取，不受引擎自带 models/ 影响。
  PYTHONPATH="$ENGINE${PYTHONPATH:+:$PYTHONPATH}" \
  "$PY" -u "$ENGINE/cli.py" \
        --input "$src" \
        --output "$TMPD/raw.wav" \
        --model "$model" \
        --hubert "$MODELS/hubert_base.pt" \
        --rmvpe "$MODELS/rmvpe.pt" \
        --pitch "$PITCH" --sid "$SPEAKER" \
        --threads "$THREADS" --chunk "$CHUNK" --pad "$PAD" \
        2>&1 \
    | tee "$PROGRESS_FILE" \
    | awk '/^\[vc \] 分块 /||/^\[f0 /||/^\[ok /||/^\[总/||/Error/||/error/||/Traceback/||/失败/ {print; fflush()}'
  local rc=${PIPESTATUS[0]}

  if [ "$rc" -ne 0 ] || [ ! -f "$TMPD/raw.wav" ]; then
    lock_release
    err "转换失败（退出码 $rc），日志：$PROGRESS_FILE"
    return 4
  fi

  # ---- 提亮 + 转格式 ----
  local final="$out"
  if have_ffmpeg; then
    if [ "$AUTO_EQ" = "1" ] && [ "$EQ" != "0" ]; then
      local pk; pk=$(awk "BEGIN{printf \"%.1f\", ${EQ}*0.6}" 2>/dev/null || echo 3)
      "$FFMPEG" -y -v error -i "$TMPD/raw.wav" \
        -af "treble=g=${EQ}:f=5500,equalizer=f=8000:t=q:w=1.2:g=${pk}" \
        -c:a "$( [ "$OUT_FMT" = mp3 ] && echo libmp3lame || echo pcm_s16le )" \
        ${OUT_FMT:+$( [ "$OUT_FMT" = mp3 ] && echo "-q:a 2" )} \
        "$final" 2>/dev/null || cp -f "$TMPD/raw.wav" "$final"
      ok "已提亮 +${EQ}dB"
    else
      "$FFMPEG" -y -v error -i "$TMPD/raw.wav" \
        -c:a "$( [ "$OUT_FMT" = mp3 ] && echo libmp3lame || echo pcm_s16le )" \
        "$final" 2>/dev/null || cp -f "$TMPD/raw.wav" "$final"
    fi
  else
    cp -f "$TMPD/raw.wav" "$final"
    warn "没有 ffmpeg，跳过提亮（转换本身已完成）"
    warn "修 ffmpeg：pkg upgrade -y && pkg install -y ffmpeg"
  fi
  rm -f "$TMPD/raw.wav"

  ok "完成：${final#$ROOT/}"
  lock_release

  if [ "$ARCHIVE_SRC" = "1" ] && [ "$(cd "$(dirname "$src")" && pwd -P)" = "$(cd "$INBOX" && pwd -P)" ]; then
    mv -f "$src" "$DONE/.源_$base" 2>/dev/null && info "  源文件已归档到 done/"
  fi
  return 0
}

# ---------- 批量 ----------
convert_all() {
  local any=0 f rc=0
  for f in "$INBOX"/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in .*) continue ;; esac
    is_audio "$f" || continue
    any=1
    convert_one "$f" || rc=$?
  done
  [ "$any" = 0 ] && info "inbox/ 里没有音频文件"
  return $rc
}

# ---------- 入口 ----------
main() {
  [ $# -eq 0 ] && { cmd_status; return 0; }
  case "$1" in
    --status|-s|status) cmd_status ;;
    --all|-a|all)       need_python; need_ffmpeg; convert_all ;;
    -h|--help|help)
      sed -n '2,12p' "$0" | sed 's/^#  \{0,2\}//'
      ;;
    -*)
      err "未知选项：$1"; exit 2 ;;
    *)
      need_python; need_ffmpeg
      local rc=0 f
      for f in "$@"; do convert_one "$f" || rc=$?; done
      return $rc
      ;;
  esac
}

main "$@"
