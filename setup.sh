#!/usr/bin/env bash
# ============================================================
#  setup.sh - 首次使用引导（交互式）
#
#  用法：bash setup.sh
#
#  它会一步步问你：模型放好了吗？要下载基础模型吗？
#  适合第一次用、不想记命令的人。
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/core.sh"

ensure_dirs
load_settings
PY="$(detect_python)" || PY=""

ask() {  # ask "问题" [y/N]
  local q="$1" d="${2:-n}" ans
  printf '  %s [%s] ' "$q" "$( [ "$d" = y ] && echo 'Y/n' || echo 'y/N')"
  read -r ans </dev/tty 2>/dev/null || ans=""
  [ -z "$ans" ] && ans="$d"
  case "$ans" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

hr
cat <<'BANNER'
  ╔══════════════════════════════════════════╗
  ║      RVC Termux Kit · 首次设置           ║
  ╚══════════════════════════════════════════╝
BANNER
hr

# ---------- 1. 环境 ----------
say "  第 1 步：检查运行环境"
say ""
if [ -n "$PY" ] && "$PY" -c 'import torch, numpy, scipy' >/dev/null 2>&1; then
  ok "Python 环境就绪（$("$PY" -V 2>&1 | cut -d' ' -f2)）"
else
  warn "Python 环境不完整"
  if ask "现在安装？（要下载约 500MB，可能要 20 分钟）" y; then
    bash "$ROOT/scripts/install.sh"
  else
    say "  稍后手动跑：bash scripts/install.sh"
    exit 1
  fi
fi

# ---------- 2. 基础模型 ----------
say ""
say "  第 2 步：基础模型（所有音色共用，约 350MB）"
say ""
miss=0
for b in hubert_base.pt rmvpe.pt; do
  [ -f "$MODELS/$b" ] || miss=$((miss+1))
done

if [ "$miss" = 0 ]; then
  ok "hubert_base.pt / rmvpe.pt 都在"
else
  warn "缺 $miss 个基础模型"
  say ""
  say "  这两个是 RVC 的公共基础模型，不随音色变化："
  say "    hubert_base.pt  181MB  内容特征"
  say "    rmvpe.pt        173MB  音高提取"
  say ""
  if ask "现在自动下载？（从 Hugging Face，国内可能较慢）" y; then
    bash "$ROOT/scripts/models.sh" fetch-base
  else
    say ""
    say "  手动下载："
    say "    https://huggingface.co/lj1995/VoiceConversionWebUI/tree/main"
    say "  下载后放进 models/ 目录，文件名保持 hubert_base.pt 和 rmvpe.pt"
    say ""
    say "  完成后重跑：bash setup.sh"
    exit 1
  fi
fi

# ---------- 3. 音色模型 ----------
say ""
say "  第 3 步：音色模型（.pth）"
say ""
cnt=$(find "$MODELS" -maxdepth 1 -name '*.pth' 2>/dev/null | wc -l)
if [ "$cnt" -gt 0 ]; then
  ok "已有 $cnt 个音色模型"
  bash "$ROOT/scripts/models.sh" list | head -20
else
  warn "还没有音色模型"
  say ""
  say "  你需要下载一个 RVC v2 模型（.pth）："
  say ""
  say "    ${C_B}https://voice-models.com/${C_0}     ← 最大模型库，免费"
  say ""
  say "  挑选要点："
  say "    · 必须是 ${C_Y}RVC v2${C_0}（v1 不支持）"
  say "    · 文件 30~80MB 是正常大小"
  say "    · 下载的可能是 .zip，解压出 .pth"
  say ""
  if ask "模型已经下载好了，现在装入？" y; then
    printf '  输入 .pth 的完整路径（可从文件管理器复制）: '
    read -r pth </dev/tty 2>/dev/null || pth=""
    if [ -n "$pth" ] && [ -f "$pth" ]; then
      bash "$ROOT/scripts/models.sh" install "$pth"
    else
      say "  没读到有效路径，稍后手动装：./models.sh install <路径>"
    fi
  else
    say "  下载后跑：./models.sh install <路径>"
  fi
fi

# ---------- 4. 性能建议 ----------
say ""
say "  第 4 步：性能参数"
say ""
gb=$(detect_mem_gb)
sc=$(suggest_chunk)
say "  你的内存：${gb}GB"
say "  建议 chunk：${sc}（决定内存峰值，越小越安全）"
cur=$(cfg chunk 4)
if [ "$cur" != "$sc" ]; then
  if ask "把 chunk 从 $cur 改成建议值 $sc？" y; then
    sed -i.bak "s|^[[:space:]]*chunk[[:space:]]*=.*|chunk = $sc|" "$CONFIG" && rm -f "$CONFIG.bak"
    ok "已更新 chunk = $sc"
  fi
else
  ok "chunk 已是建议值"
fi

# ---------- 5. 完成 ----------
say ""
hr
ok "设置完成"
hr
say ""
say "  开始用："
say ""
say "    ./rvc-kit convert <音频文件>     转换一个文件"
say "    ./rvc-kit                         看状态和进度"
say ""
say "  或者丢文件自动转："
say ""
say "    ./rvc-kit watch                  前台监听 inbox/"
say ""
say "  详细用法见 README.md"
say ""
