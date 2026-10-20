#!/usr/bin/env bash
# ============================================================
#  models.sh - 模型管理：查看 / 安装 / 切换 / 校验
#
#  用法：
#     ./models.sh list                     列出已装的音色模型
#     ./models.sh use <名字>               切换当前使用的模型
#     ./models.sh install <pth路径>        装入一个 .pth（可从任意位置）
#     ./models.sh base                     检查基础模型（hubert/rmvpe）
#     ./models.sh info <名字>              看某个模型的详情
#
#  术语区分：
#     「音色模型」= 你从网上下载的 .pth（每个音色一个，几十 MB）
#     「基础模型」= hubert_base.pt + rmvpe.pt（所有音色共用，约 350MB）
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
load_settings

VOCAL_DIR="$MODELS"

# ---------------- list ----------------
cmd_list() {
  local n=0 f sz name cur
  cur=$(cfg model "")
  hr; say "  已装的音色模型（${VOCAL_DIR#$ROOT/}/）"; hr
  for f in "$VOCAL_DIR"/*.pth; do
    [ -e "$f" ] || continue
    n=$((n+1))
    name="${f##*/}"
    sz=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [ "$name" = "$cur" ]; then
      printf '  %s●%s %-40s %5d MB  ← 当前使用\n' "$C_G" "$C_0" "$name" "$(( sz / 1048576 ))"
    else
      printf '  %s○%s %-40s %5d MB\n' "$C_D" "$C_0" "$name" "$(( sz / 1048576 ))"
    fi
  done
  [ "$n" = 0 ] && {
    warn "还没有音色模型"
    say "  下载一个（免费）：https://voice-models.com/"
    say "  然后：./models.sh install /path/to/xxx.pth"
  }

  say ""
  say "  基础模型（所有音色共用）"
  for b in hubert_base.pt rmvpe.pt; do
    f="$VOCAL_DIR/$b"
    if [ -f "$f" ]; then
      sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
      printf '    %s✓%s %-24s %5d MB\n' "$C_G" "$C_0" "$b" "$(( sz / 1048576 ))"
    else
      printf '    %s✗%s %-24s 缺失\n' "$C_R" "$C_0" "$b"
    fi
  done

  say ""
  say "  索引文件（.index，可选）"
  local idx=0 i
  for i in "$VOCAL_DIR"/*.index; do
    [ -e "$i" ] || continue
    idx=$((idx+1))
    sz=$(stat -c%s "$i" 2>/dev/null || echo 0)
    printf '    %s %5d MB\n' "${i##*/}" "$(( sz / 1048576 ))"
  done
  [ "$idx" = 0 ] && printf '    %s无（不影响转换，只是少一点音色相似度提升）%s\n' "$C_D" "$C_0"
  hr
}

# ---------------- use ----------------
cmd_use() {
  local want="${1:-}"
  [ -n "$want" ] || die "用法：./models.sh use <模型文件名或关键词>"
  local found="" f name hits=0 last=""
  # 1) 完整文件名
  if [ -f "$VOCAL_DIR/$want" ]; then
    found="$want"
  elif [ -f "$VOCAL_DIR/$want.pth" ]; then
    found="$want.pth"
  else
    # 2) 模糊匹配（子串，不区分大小写）
    local lw; lw=$(printf '%s' "$want" | tr 'A-Z' 'a-z')
    for f in "$VOCAL_DIR"/*.pth; do
      [ -e "$f" ] || continue
      name="${f##*/}"
      case "$(printf '%s' "$name" | tr 'A-Z' 'a-z')" in
        *"$lw"*) hits=$((hits+1)); last="$name" ;;
      esac
    done
    if [ "$hits" -eq 1 ]; then
      found="$last"
    elif [ "$hits" -gt 1 ]; then
      err "「$want」匹配到 $hits 个，请写得更具体："
      for f in "$VOCAL_DIR"/*.pth; do
        [ -e "$f" ] || continue
        name="${f##*/}"
        case "$(printf '%s' "$name" | tr 'A-Z' 'a-z')" in *"$lw"*) echo "    $name" ;; esac
      done
      exit 1
    else
      err "没找到匹配「$want」的模型"
      info "看现有模型：./models.sh list"
      exit 1
    fi
  fi

  # 写回 config.ini
  if grep -qE '^[[:space:]]*model[[:space:]]*=' "$CONFIG" 2>/dev/null; then
    sed -i.bak "s|^[[:space:]]*model[[:space:]]*=.*|model = ${found}|" "$CONFIG" && rm -f "$CONFIG.bak"
  else
    printf '\nmodel = %s\n' "$found" >> "$CONFIG"
  fi
  ok "已切换到：$found"
  info "  （config.ini 里的 model= 已更新）"
}

# ---------------- install ----------------
cmd_install() {
  local src="$1" dst base
  [ -n "$src" ] || die "用法：./models.sh install <xxx.pth 路径>"
  [ -f "$src" ] || die "找不到文件：$src"
  case "$(printf '%s' "${src##*.}" | tr 'A-Z' 'a-z')" in
    pth|pt) ;;
    *) die "只接受 .pth 或 .pt 文件（当前：${src##*.}）" ;;
  esac
  base="${src##*/}"

  # 体积合理性检查：真正的 RVC 音色模型 30~80MB
  local sz; sz=$(stat -c%s "$src" 2>/dev/null || echo 0)
  if [ "$sz" -lt 5000000 ]; then
    warn "文件只有 $(( sz / 1048576 ))MB，RVC 模型通常 30~80MB"
    warn "  小文件可能是下载失败的 HTML 页面，或不是 RVC 模型"
    printf '  继续吗？[y/N] '
    read -r ans
    case "$ans" in y|Y) ;; *) die "已取消" ;; esac
  fi
  if [ "$sz" -gt 400000000 ]; then
    warn "文件 $(( sz / 1048576 ))MB，比一般音色模型大很多（可能下错了）"
  fi

  dst="$VOCAL_DIR/$base"
  if [ -f "$dst" ]; then
    local dsz; dsz=$(stat -c%s "$dst" 2>/dev/null || echo 0)
    info "已存在同名模型（$(( dsz / 1048576 ))MB），覆盖？[y/N] "
    read -r ans
    case "$ans" in y|Y) ;; *) info "保留原文件"; return 0 ;; esac
  fi

  cp -f "$src" "$dst" || die "复制失败"
  ok "已装入：$base"
  info "  位置：${dst#$ROOT/}"

  # 同目录下如果有同名 .index，一起拿过来
  local idxsrc idxbase
  idxbase="${base%.*}"
  for idxsrc in "$(dirname "$src")"/*.index; do
    [ -e "$idxsrc" ] || continue
    case "${idxsrc##*/}" in
      *"$idxbase"*)
        cp -f "$idxsrc" "$VOCAL_DIR/" 2>/dev/null && \
          info "  连带装入索引：${idxsrc##*/}"
        ;;
    esac
  done

  # 只有一个模型时自动切过去；多个则问
  local cnt; cnt=$(find "$VOCAL_DIR" -maxdepth 1 -name '*.pth' 2>/dev/null | wc -l)
  if [ "$cnt" -le 1 ]; then
    cmd_use "$base" >/dev/null 2>&1 && info "  已自动设为当前模型"
  else
    info "  切换到这个模型：./models.sh use $base"
  fi
}

# ---------------- base ----------------
cmd_base() {
  hr; say "  基础模型检查"; hr
  local ok_all=1
  for b in hubert_base.pt rmvpe.pt; do
    if [ -f "$VOCAL_DIR/$b" ]; then
      local sz; sz=$(stat -c%s "$VOCAL_DIR/$b" 2>/dev/null || echo 0)
      printf '  %s✓%s %-20s %5d MB\n' "$C_G" "$C_0" "$b" "$(( sz / 1048576 ))"
    else
      printf '  %s✗%s %-20s 缺失\n' "$C_R" "$C_0" "$b"
      ok_all=0
    fi
  done
  if [ "$ok_all" = 0 ]; then
    say ""
    say "  这两个是 RVC 的公共基础模型（不随音色变化），必须要有："
    say "    hubert_base.pt  约 181MB  内容特征提取"
    say "    rmvpe.pt        约 173MB  音高提取"
    say ""
    say "  来源（任选一，注意核对文件名必须是上面两个）："
    say "    https://huggingface.co/lj1995/VoiceConversionWebUI/tree/main"
    say "    https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/releases"
    say ""
    say "  下载后放进 ${VOCAL_DIR#$ROOT/}/ 即可，无需改名以外的操作。"
    say "  也可以用：./models.sh fetch-base   （自动尝试下载，见下）"
    return 1
  fi
  ok "基础模型齐全"
  return 0
}

# ---------------- fetch-base ----------------
cmd_fetch_base() {
  need_python
  local hf="https://huggingface.co/lj1995/VoiceConversionWebUI/resolve/main"
  hr; say "  下载基础模型"; hr
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "需要 curl 或 wget。Termux: pkg install -y curl"
  fi
  for pair in "hubert_base.pt:$hf/hubert_base.pt" "rmvpe.pt:$hf/rmvpe.pt"; do
    local name="${pair%%:*}" url="${pair#*:}"
    if [ -f "$VOCAL_DIR/$name" ]; then
      ok "$name 已存在，跳过"
      continue
    fi
    info "  下载 $name …"
    if command -v curl >/dev/null 2>&1; then
      curl -L --fail --progress-bar -o "$VOCAL_DIR/$name.part" "$url" || \
        { rm -f "$VOCAL_DIR/$name.part"; err "$name 下载失败，请手动下载"; continue; }
    else
      wget -O "$VOCAL_DIR/$name.part" "$url" || \
        { rm -f "$VOCAL_DIR/$name.part"; err "$name 下载失败，请手动下载"; continue; }
    fi
    mv -f "$VOCAL_DIR/$name.part" "$VOCAL_DIR/$name"
    ok "$name 完成（$(( $(stat -c%s "$VOCAL_DIR/$name") / 1048576 ))MB）"
  done
  cmd_base || true
}

# ---------------- info ----------------
cmd_info() {
  local want="${1:-}"
  [ -n "$want" ] || die "用法：./models.sh info <模型文件名>"
  local f="$VOCAL_DIR/$want"
  [ -f "$f" ] || f="$VOCAL_DIR/$want.pth"
  [ -f "$f" ] || die "找不到：$want"
  need_python
  hr; say "  ${f##*/}"; hr
  local sz; sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
  printf '  大小      %d MB\n' "$(( sz / 1048576 ))"

  local pyf="$TMPD/.modelinfo.py"
  cat > "$pyf" <<'PYEOF_INNER'
import sys, warnings, re
warnings.filterwarnings("ignore")
import torch
try:
    ck = torch.load(sys.argv[1], map_location="cpu", weights_only=False)
except Exception as e:
    print("LOADFAIL %s" % e); sys.exit(0)
inner = ck.get("weight") if isinstance(ck, dict) and "weight" in ck else ck
def g(k, d=None):
    try: return ck.get(k, d)
    except Exception: return d
sr  = g("sr"); f0 = g("f0"); ver = g("version"); inf = g("info"); cfg = g("config")
print("采样率    %s" % (sr if sr else "?"))
print("f0模式    %s" % ("是" if f0 else "否"))
print("版本      %s" % (ver if ver else "?"))
print("备注      %s" % (inf if inf else "?"))
if isinstance(cfg, (list, tuple)) and cfg:
    print("结构参数  %s" % (", ".join(str(x) for x in cfg)))
spk = "?"
try:
    for k, v in inner.items():
        if "emb_g" in k and hasattr(v, "shape") and v.dim() > 0:
            spk = v.shape[0]; break
except Exception:
    pass
print("说话人数  %s" % spk)
PYEOF_INNER
  "$PY" "$pyf" "$f" 2>/dev/null | while IFS= read -r ln; do printf '  %s\n' "$ln"; done
  rm -f "$pyf"
  hr
}

# ---------------- 入口 ----------------
case "${1:-}" in
  list|ls|l)   cmd_list ;;
  use|u)       shift; cmd_use "${1:-}" ;;
  install|add|i)
               shift; cmd_install "${1:-}" ;;
  base|b)      cmd_base ;;
  fetch-base|fetch)
               cmd_fetch_base ;;
  info|show)   shift; cmd_info "${1:-}" ;;
  ""|-h|--help|help)
    sed -n '/^# ====/,/^# ====.*$/p' "$0" | sed 's/^#  \{0,2\}//' | sed '1d;$d'
    ;;
  *) die "未知子命令：$1（跑 ./models.sh 看用法）" ;;
esac
