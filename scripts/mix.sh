#!/usr/bin/env bash
# ============================================================
#  mix.sh - 把转换后的人声和伴奏混成成品
#
#  用法：
#     ./mix.sh <人声> <伴奏> [输出]
#     ./mix.sh <人声> <伴奏> [输出] <参照人声> [前推dB]
#
#  参照人声（可选）：原始的人声轨。给了就按它的响度对齐，
#  混出来整体响度跟原曲一致，不会人声盖过伴奏或人声太小。
#  不给则保守地压到伴奏 -3dB。
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
load_settings
need_ffmpeg

[ $# -lt 2 ] && { sed -n '2,14p' "$0" | sed 's/^#  \{0,2\}//'; exit 1; }

VOC="$1"; INST="$2"
OUTW="${3:-}"
REF="${4:-}"
EXTRA_DB="${5:-$EXTRA}"

[ -f "$VOC" ]  || die "找不到人声：$VOC"
[ -f "$INST" ] || die "找不到伴奏：$INST"
[ -n "$REF" ]  && { [ -f "$REF" ] || die "找不到参照人声：$REF"; }

case "$EXTRA_DB" in ''|*[!0-9.-]*) EXTRA_DB="$EXTRA" ;; esac

# ---- 时长检查：差太多说明没对齐，先警告 ----
pb=$(ffprobe_bin)
if [ -n "$pb" ] && [ -x "$pb" ]; then
  dv=$("$pb" -v error -show_entries format=duration -of csv=p=0 "$VOC" 2>/dev/null | cut -d. -f1)
  di=$("$pb" -v error -show_entries format=duration -of csv=p=0 "$INST" 2>/dev/null | cut -d. -f1)
  if [ -n "${dv:-}" ] && [ -n "${di:-}" ]; then
    diff=$(( dv > di ? dv - di : di - dv ))
    printf '  人声 %ss   伴奏 %ss   相差 %ss\n' "$dv" "$di" "$diff"
    [ "$diff" -gt 3 ] && warn "两者时长差 ${diff}s，可能有对不齐的地方，成品请自查"
  fi
fi

# ---- 平均音量 ----
mean_db() {
  "$FFMPEG" -hide_banner -nostats -i "$1" -af volumedetect -f null - 2>&1 \
    | grep -m1 mean_volume | sed 's/.*mean_volume:[[:space:]]*//; s/[[:space:]]*dB//'
}

van=$(mean_db "$VOC"); ian=$(mean_db "$INST")
printf '  人声平均音量  %s dB\n' "$van"
printf '  伴奏平均音量  %s dB\n' "$ian"

if [ -n "$REF" ]; then
  ran=$(mean_db "$REF")
  printf '  参照人声      %s dB\n' "$ran"
  gain=$(awk "BEGIN{printf \"%.2f\", ${ran} - ${van} + ${EXTRA_DB}}")
  printf '  人声增益      %s dB（对齐参照 + 前推 %s dB）\n' "$gain" "$EXTRA_DB"
else
  gain=$(awk "BEGIN{printf \"%.2f\", ${ian} - 3 - ${van} + ${EXTRA_DB}}")
  printf '  人声增益      %s dB（无参照，按伴奏 -3dB + 前推 %s dB）\n' "$gain" "$EXTRA_DB"
fi

[ -z "$OUTW" ] && OUTW="$OUTBOX/$(basename "${VOC%.*}")_mix.wav"
mkdir -p "$(dirname "$OUTW")"

# ---- 混音：保住立体声 ----
# 人声是单声道：复制成左右双声道，不要让它把伴奏压成单声道。
# normalize=0 保住算好的比例；不用 alimiter（它有前瞻延迟会让整轨位移）。
TMPW="$TMPD/.mix.wav"
"$FFMPEG" -y -loglevel error -i "$VOC" -i "$INST" \
  -filter_complex "[0:a]volume=${gain}dB,aresample=44100,pan=stereo|c0=c0|c1=c0[v];[1:a]aresample=44100[i];[v][i]amix=inputs=2:duration=longest:normalize=0[out]" \
  -map "[out]" -c:a pcm_s16le "$TMPW" || { rm -f "$TMPW"; die "混音失败"; }

# ---- 峰值保护：整体静态降增益，保波形不变形 ----
peak=$("$FFMPEG" -hide_banner -nostats -i "$TMPW" -af volumedetect -f null - 2>&1 \
       | grep -m1 max_volume | sed 's/.*max_volume:[[:space:]]*//; s/[[:space:]]*dB//')
red=$(awk "BEGIN{p=${peak}; if (p > -1.0) printf \"%.2f\", -1.0 - p; else printf \"0\"}")
if [ "$red" != "0" ] && [ "$red" != "0.00" ]; then
  printf '  峰值 %s dB 偏高，整体降 %s dB\n' "$peak" "$red"
  "$FFMPEG" -y -loglevel error -i "$TMPW" -af "volume=${red}dB" -c:a pcm_s16le "$OUTW" || die "降增益失败"
  rm -f "$TMPW"
else
  mv -f "$TMPW" "$OUTW"
fi

ok "已输出 ${OUTW#$ROOT/}"
if [ -n "$pb" ] && [ -x "$pb" ]; then
  "$pb" -v error -show_entries format=duration -of default=nw=1 "$OUTW" 2>/dev/null | sed 's/^/  /'
fi
"$FFMPEG" -hide_banner -nostats -i "$OUTW" -af volumedetect -f null - 2>&1 \
  | grep -E "mean_volume|max_volume" | sed 's/.*\] /  /'
