#!/usr/bin/env bash
# ============================================================
#  split.sh - 从原曲里分离出伴奏（人声消除）
#
#  用法：
#     ./split.sh <原曲> <输出伴奏> [参考人声]
#
#  原理：原曲 = 人声 + 伴奏。中置声道相位相消能去掉居中人声，
#  得到伴奏。这是"数学减法"，不是 AI 分离，所以：
#    · 对立体声混音良好的歌效果好（大部分商业歌曲）
#    · 对单声道源、或人声不在正中的现场版效果差
#
#  更好的做法：用 https://vocalremover.org 之类先分出干净人声，
#  再用 ./split.sh 或直接用它给的伴奏。
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
need_ffmpeg

[ $# -lt 2 ] && { sed -n '2,17p' "$0" | sed 's/^#  \{0,2\}//'; exit 1; }

SRC="$1"; OUTI="$2"; REF="${3:-}"
[ -f "$SRC" ] || die "找不到原曲：$SRC"
mkdir -p "$(dirname "$OUTI")"

PB=$(ffprobe_bin)
if [ -n "$PB" ]; then
  ch=$("$PB" -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$SRC" 2>/dev/null)
  [ "${ch:-2}" -lt 2 ] && warn "源是单声道，相位相消失效（需要立体声）"
fi

info "  正在分离伴奏…"
# aresample 保证两轨采样率一致，否则 amix 会错位
"$FFMPEG" -y -v error -i "$SRC" -i "$SRC" \
  -filter_complex "[0:a]aresample=44100[a];[1:a]aresample=44100,volume=-1[b];[a][b]amix=inputs=2:duration=longest:normalize=0[out]" \
  -map "[out]" -c:a pcm_s16le "$OUTI" || die "分离失败"

ok "已输出 $OUTI"

# 有参考人声就报告残差（检查分离质量）
if [ -n "$REF" ] && [ -f "$REF" ]; then
  info "  检查分离质量（与原曲的残差）…"
  T1="$TMPD/.s1.wav"; T2="$TMPD/.s2.wav"
  "$FFMPEG" -y -v error -i "$SRC" -ac 1 -ar 16000 -c:a pcm_s16le "$T1" 2>/dev/null
  "$FFMPEG" -y -v error -i "$OUTI" -i "$REF" -filter_complex "[0:a][1:a]amix=inputs=2:duration=shortest:normalize=0" \
    -ac 1 -ar 16000 -c:a pcm_s16le "$T2" 2>/dev/null
  P="${PY:-$(detect_python)}"
  if [ -n "$P" ]; then
    "$P" - "$T1" "$T2" <<'PY' 2>/dev/null || true
import sys
import numpy as np
from scipy.io import wavfile
_, a = wavfile.read(sys.argv[1]); _, b = wavfile.read(sys.argv[2])
n = min(len(a), len(b))
a = a[:n].astype(np.float64); b = b[:n].astype(np.float64)
err = np.sqrt(((a-b)**2).mean()) / (np.sqrt((a**2).mean()) + 1e-9)
print(f"  重建误差 {err*100:.2f}%（越小越好，<1% 说明分离很干净）")
PY
  fi
  rm -f "$T1" "$T2"
fi
