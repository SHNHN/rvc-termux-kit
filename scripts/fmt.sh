#!/usr/bin/env bash
# ============================================================
#  fmt.sh - 音频格式处理小工具
#
#  用法：
#     ./fmt.sh to-wav <输入> [输出]      转成标准 wav（16bit 44.1k）
#     ./fmt.sh trim <输入> [秒] [输出]   剪掉尾部静音
#     ./fmt.sh probe <输入>              看时长/采样率/声道
#     ./fmt.sh loudness <输入>           看平均/峰值音量
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
need_ffmpeg
PB=$(ffprobe_bin)

sub="${1:-}"; shift 2>/dev/null || true

case "$sub" in
  to-wav)
    [ $# -lt 1 ] && die "用法：./fmt.sh to-wav <输入> [输出]"
    src="$1"
    [ -f "$src" ] || die "找不到：$src"
    out="${2:-$OUTBOX/$(basename "${src%.*}").wav}"
    mkdir -p "$(dirname "$out")"
    "$FFMPEG" -y -v error -i "$src" -vn -c:a pcm_s16le -ar 44100 "$out" || die "转换失败"
    ok "已输出 $out"
    ;;

  trim)
    # 智能剪掉尾部静音：用谱特征判断"音乐"还是"底噪"
    [ $# -lt 1 ] && die "用法：./fmt.sh trim <输入> [保留余量秒] [输出]"
    src="$1"
    [ -f "$src" ] || die "找不到：$src"
    tail_s="${2:-1.5}"
    out="${3:-$OUTBOX/$(basename "${src%.*}")_trim.${src##*.}}"
    mkdir -p "$(dirname "$out")"
    source_py="${PY:-$(detect_python)}"
    [ -n "$source_py" ] || die "需要 python 来做检测。没装就先手动用 ffmpeg -t"

    "$source_py" - "$src" "$tail_s" "$out" "$FFMPEG" <<'PY'
import sys, os, subprocess, tempfile
import numpy as np
src, tail_s, out, ffmpeg = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
try:
    from scipy.io import wavfile
    from scipy import signal
except Exception:
    print("需要 numpy 和 scipy", file=sys.stderr); sys.exit(1)

with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
    tmp = t.name
try:
    subprocess.run([ffmpeg, "-y", "-v", "error", "-i", src,
                    "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", tmp], check=True)
    _, d = wavfile.read(tmp)
    x = d.astype(np.float64)
    total = len(x) / 44100.0
    # 逐秒判断：谱质心低 + 谱平坦度低 = 音乐；否则是宽带底噪
    last_music = 0.0
    for sec in range(int(total)):
        seg = x[sec*44100:(sec+1)*44100]
        if len(seg) < 4096:
            break
        fr, P = signal.welch(seg, 44100, nperseg=4096)
        P = P + 1e-20
        flat = float(np.exp(np.log(P).mean()) / P.mean())
        cent = float((fr * P).sum() / P.sum())
        if cent < 4000 and flat < 0.05:
            last_music = sec + 1.0
    if last_music <= 0:
        print("没检测到音乐内容，不做裁剪", file=sys.stderr)
        sys.exit(2)
    end = min(total, last_music + tail_s)
    print(f"  内容结束 {last_music:.1f}s   总长 {total:.1f}s   剪到 {end:.2f}s")
    ext = os.path.splitext(out)[1].lower()
    codec = ["-c:a", "libmp3lame", "-q:a", "2"] if ext == ".mp3" else ["-c:a", "pcm_s16le"]
    subprocess.run([ffmpeg, "-y", "-v", "error", "-i", src, "-t", f"{end:.2f}"] + codec + [out], check=True)
    print(f"  已输出 {out}")
finally:
    try: os.unlink(tmp)
    except OSError: pass
PY
    ;;

  probe)
    [ $# -lt 1 ] && die "用法：./fmt.sh probe <输入>"
    src="$1"; [ -f "$src" ] || die "找不到：$src"
    say "  文件    ${src##*/}"
    [ -n "$PB" ] && "$PB" -v error -show_entries format=duration,size \
        -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 "$src" | sed 's/^/  /'
    ;;

  loudness)
    [ $# -lt 1 ] && die "用法：./fmt.sh loudness <输入>"
    src="$1"; [ -f "$src" ] || die "找不到：$src"
    "$FFMPEG" -hide_banner -nostats -i "$src" -af volumedetect -f null - 2>&1 \
      | grep -E "mean_volume|max_volume" | sed 's/.*\] /  /'
    ;;

  ""|-h|--help) sed -n '2,10p' "$0" | sed 's/^#  \{0,2\}//' ;;
  *) die "未知子命令：$sub" ;;
esac
