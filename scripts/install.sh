#!/usr/bin/env bash
# ============================================================
#  install.sh - 一键安装运行环境
#
#  做四件事：
#    1. 检测架构 / Python 版本 / 可用内存，给出该用哪条安装路线
#    2. 装系统包（python、ffmpeg、libsndfile）
#    3. 装 Python 依赖（**有讲究**，见下方注释）
#    4. 真实跑一次 2 秒转换验证，通过才报成功
#
#  用法：
#     bash scripts/install.sh            完整安装
#     bash scripts/install.sh --check    只检测，不安装
#     bash scripts/install.sh --deps     跳过系统包，只补 Python 依赖
# ============================================================
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/core.sh"

ensure_dirs
load_settings

IS_TERMUX=0
[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] && IS_TERMUX=1
[ "$(uname -o 2>/dev/null)" = "Android" ] && IS_TERMUX=1

MODE="${1:-}"

# ------------------------------------------------------------
#  一、环境检测
# ------------------------------------------------------------
detect_env() {
  hr
  say "  环境检测"
  hr

  local arch os pyver memkb memgb
  arch=$(uname -m 2>/dev/null || echo unknown)
  os=$(uname -s 2>/dev/null || echo unknown)
  printf '  %-12s %s\n' "系统" "$os $( [ "$IS_TERMUX" = 1 ] && echo '(Termux/Android)')"
  printf '  %-12s %s\n' "架构" "$arch"

  memkb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
  memgb=$(( ${memkb:-0} / 1024 / 1024 ))
  printf '  %-12s %s GB\n' "内存" "$memgb"

  # --- Python ---
  PY="$(detect_python)" || PY=""
  if [ -z "$PY" ]; then
    printf '  %-12s %s\n' "Python" "未安装"
    pyver="none"
  else
    pyver=$("$PY" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null || echo "?")
    printf '  %-12s %s  (%s)\n' "Python" "$pyver" "$PY"
  fi

  # --- 逐项依赖 ---
  printf '\n  依赖状态\n'
  local item status
  check() {  # check <名字> <python表达式>
    local nm="$1" expr="$2"
    if [ -z "$PY" ]; then printf '    %-16s %s✗%s 无 python\n' "$nm" "$C_R" "$C_0"; return 1; fi
    if "$PY" -c "import $expr" >/dev/null 2>&1; then
      printf '    %-16s %s✓%s\n' "$nm" "$C_G" "$C_0"; return 0
    else
      printf '    %-16s %s✗%s\n' "$nm" "$C_R" "$C_0"; return 1
    fi
  }

  local missing=""
  check "torch"  "torch"        || missing="$missing torch"
  check "numpy"  "numpy"        || missing="$missing numpy"
  check "scipy"  "scipy"        || missing="$missing scipy"
  # 以下三个是 torch 启动就必须的，缺了会 ModuleNotFoundError
  check "typing_extensions" "typing_extensions" || missing="$missing typing_extensions"
  check "filelock" "filelock"   || missing="$missing filelock"

  if have_ffmpeg; then
    printf '    %-16s %s✓%s  %s\n' "ffmpeg" "$C_G" "$C_0" "$("$FFMPEG" -version 2>/dev/null | head -1 | cut -c1-40)"
  else
    printf '    %-16s %s✗%s\n' "ffmpeg" "$C_R" "$C_0"
    missing="$missing ffmpeg"
  fi

  # --- 给出建议 ---
  printf '\n  建议设置（按你的内存）\n'
  local sc; sc=$(suggest_chunk)
  printf '    chunk  %s   （内存 %sGB 对应的安全值）\n' "$sc" "$memgb"
  if [ "$memgb" -gt 0 ] && [ "$memgb" -lt 4 ]; then
    printf '    低配机器：threads 建议 3，chunk 建议 3\n'
  elif [ "$memgb" -lt 7 ]; then
    printf '    中配机器：threads 4，chunk 4（默认值可用）\n'
  else
    printf '    高配机器：threads 6~8，chunk 可以试 8\n'
  fi

  MISSING="$missing"
  PYVER="$pyver"
  ARCH="$arch"
}

detect_env

if [ "$MODE" = "--check" ]; then
  printf '\n  缺的组件：%s\n' "${MISSING:-无}"
  exit 0
fi

# ------------------------------------------------------------
#  二、系统包
# ------------------------------------------------------------
install_system() {
  hr; say "  安装系统包"; hr

  if [ "$IS_TERMUX" = 1 ]; then
    if ! command -v pkg >/dev/null 2>&1; then
      die "找不到 pkg，这看起来不像 Termux"
    fi
    # 换源（可选，但官方源在国内经常慢到没法用）
    if [ "${SKIP_REPO:-0}" != "1" ]; then
      warn "如果你在国内且下载很慢，另开一个终端跑：termux-change-repo"
      warn "  选 Mirror group → TUNA(清华) 或 USTC(中科大)"
    fi
    info "  更新软件源…"
    pkg update -y >/dev/null 2>&1 || warn "pkg update 有报错，继续"

    info "  安装 python / ffmpeg / libsndfile…"
    pkg install -y python ffmpeg libsndfile 2>&1 | tail -5

    # numpy/scipy 优先用 Termux 的预编译包（比 pip 快得多，且不会编译失败）
    info "  安装 numpy / scipy（Termux 预编译版）…"
    pkg install -y python-numpy 2>/dev/null || true
    pkg install -y python-scipy 2>/dev/null || true
  else
    if command -v apt-get >/dev/null 2>&1; then
      info "  用 apt 安装…"
      sudo apt-get update -y >/dev/null 2>&1 || apt-get update -y >/dev/null 2>&1 || true
      sudo apt-get install -y python3 python3-pip ffmpeg libsndfile1 \
        || apt-get install -y python3 python3-pip ffmpeg libsndfile1 || warn "系统包装载失败，继续"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y python3 python3-pip ffmpeg libsndfile || warn "系统包装载失败，继续"
    elif command -v brew >/dev/null 2>&1; then
      brew install python ffmpeg libsndfile || warn "brew 装载失败，继续"
    else
      warn "没认出包管理器，请手动安装：python3 pip ffmpeg libsndfile"
    fi
  fi

  # 重新探测
  PY="$(detect_python)" || PY=""
  FFMPEG="$(detect_ffmpeg)" || FFMPEG=""
}

# ------------------------------------------------------------
#  三、Python 依赖
#
#  这里的顺序和取舍是踩过坑的，别随便改：
#   · torch 优先用系统包（Termux: python-torch）。pip 装的 manylinux
#     wheel 在 Android 上用不了。
#   · **不要装 sympy / networkx**：它们是 torch 的元数据依赖，
#     推理根本用不到，却要下 77MB+19MB。用 --no-deps 跳过。
#   · **不要 pip 装 soxr**：它从源码编译，手机上要 3~10 分钟，
#     而且引擎有 scipy 兜底，装了纯属浪费时间。
#   · soundfile 也不需要：引擎直接 ctypes 调系统 libsndfile。
# ------------------------------------------------------------
install_python_deps() {
  hr; say "  安装 Python 依赖"; hr

  PY="$(detect_python)" || PY=""
  [ -n "$PY" ] || die "还是找不到 python3"

  local pv
  pv=$("$PY" -c 'import sys;print(sys.version_info[0]*100+sys.version_info[1])' 2>/dev/null || echo 0)
  if [ "$pv" -lt 310 ]; then
    die "Python 版本太低（$("$PY" -V 2>&1)）。RVC 需要 3.10+"
  fi
  info "  Python $("$PY" -V 2>&1 | cut -d' ' -f2)"

  # --- torch ---
  if "$PY" -c 'import torch' >/dev/null 2>&1; then
    ok "torch 已可用：$("$PY" -c 'import torch;print(torch.__version__)' 2>/dev/null)"
  else
    info "  安装 torch…"
    if [ "$IS_TERMUX" = 1 ]; then
      pkg install -y python-torch 2>&1 | tail -3 || true
    fi
    if ! "$PY" -c 'import torch' >/dev/null 2>&1; then
      info "  Termux 包不行，试 pip（仅 x86_64/ARM64 的 manylinux wheel 有效）…"
      "$PY" -m pip install --no-cache-dir --no-deps torch 2>&1 | tail -3 || true
    fi
  fi

  # --- torch 的小依赖（缺一个就 ModuleNotFoundError）---
  # 用 --no-deps 是关键：否则 pip 会追着把 sympy 77MB 也下了
  local need_more=""
  for m in typing_extensions filelock fsspec jinja2; do
    "$PY" -c "import $m" >/dev/null 2>&1 || need_more="$need_more $m"
  done
  if [ -n "$need_more" ]; then
    info "  补 torch 依赖：$need_more"
    "$PY" -m pip install --no-cache-dir --no-deps $need_more 2>&1 | tail -3 || \
      warn "pip 装这几个失败了，可以先跳过（不影响 import 就先不管）"
  fi

  # --- numpy / scipy ---
  for m in numpy scipy; do
    if "$PY" -c "import $m" >/dev/null 2>&1; then
      ok "$m 已可用：$("$PY" -c "import $m;print($m.__version__)" 2>/dev/null)"
    else
      info "  安装 $m…"
      "$PY" -m pip install --no-cache-dir "$m" 2>&1 | tail -3 || warn "$m 装载失败"
    fi
  done
}

if [ "$MODE" = "--deps" ]; then
  install_python_deps
else
  install_system
  install_python_deps
fi

# ------------------------------------------------------------
#  四、引擎（从上游拉取）
# ------------------------------------------------------------
install_engine() {
  hr; say "  检查推理引擎"; hr

  if [ -f "$ENGINE/cli.py" ]; then
    ok "引擎已就位：${ENGINE#$ROOT/}/"
    return 0
  fi

  warn "没找到 ${ENGINE#$ROOT/}/infer.py"
  say ""
  say "  本仓库不含 RVC 引擎源码（它属于上游项目，按其许可证单独分发）。"
  say "  请从上游获取 Retrieval-based-Voice-Conversion-WebUI，然后把需要的部分放到："
  say "    ${ENGINE#$ROOT/}/infer.py          推理主程序"
  say "    ${ENGINE#$ROOT/}/lib/             模型定义"
  say "    ${ENGINE#$ROOT/}/hubert/          HuBERT 特征提取"
  say "    ${ENGINE#$ROOT/}/rmvpe/           音高提取"
  say ""
  say "  详见 README.md 的「引擎准备」一节。"
  return 1
}

install_engine || true

# ------------------------------------------------------------
#  五、模型
# ------------------------------------------------------------
check_model() {
  hr; say "  检查模型"; hr
  local m
  if m=$(resolve_model); then
    ok "模型：${m#/}"
    say "    （config.ini 里写的：$MODEL_NAME）"
    local idx
    idx=$(find "$MODELS" -maxdepth 1 -name '*.index' 2>/dev/null | head -1)
    if [ -n "$idx" ]; then
      info "  发现 .index：$(basename "$idx")"
      info "    · 它需要 faiss 才能用，手机端一般不装，忽略即可"
      info "    · 不影响正常转换"
    fi
  else
    warn "没有找到 .pth 模型"
    say "  把你的 RVC v2 模型放进 ${MODELS#$ROOT/}/ ，然后在 config/config.ini 里"
    say "  把 model = 改成对应文件名（也可以把文件命名为 config 里写的名字）。"
    return 1
  fi
}
HAVE_MODEL=0
check_model && HAVE_MODEL=1

# ------------------------------------------------------------
#  六、真实验证
# ------------------------------------------------------------
verify() {
  hr; say "  端到端验证"; hr

  [ "$HAVE_MODEL" = 1 ] || { warn "没有模型，跳过验证"; return 1; }
  [ -f "$ENGINE/cli.py" ] || { warn "没有引擎，跳过验证"; return 1; }

  # 造一段 2 秒的测试音（正弦扫频），不依赖任何外部素材
  local src="$TMPD/._install_test.wav"
  if have_ffmpeg; then
    "$FFMPEG" -y -v error -f lavfi -i "sine=frequency=440:duration=2" \
      -ar 44100 -ac 1 -c:a pcm_s16le "$src" 2>/dev/null \
      || "$FFMPEG" -y -v error -f lavfi -i "sine=frequency=440:duration=2" -c:a pcm_s16le "$src"
  else
    warn "没有 ffmpeg，造不出测试音，跳过验证"
    return 1
  fi

  info "  转换 2 秒测试音（约 1 分钟，主要花在加载模型）…"
  local outp="$TMPD/._install_out.wav"
  "$PY" -u "$ENGINE/cli.py" --input "$src" --output "$outp" \
        --model "$(resolve_model)" --pitch 0 --sid "$SPEAKER" \
        --threads "$THREADS" --chunk "$CHUNK" --pad "$PAD" \
        --hubert "$MODELS/hubert_base.pt" --rmvpe "$MODELS/rmvpe.pt" \
        2>&1 | tail -6

  if [ -f "$outp" ]; then
    ok "转换成功，输出 $(stat -c%s "$outp" 2>/dev/null || echo '?') 字节"
    rm -f "$outp" "$src"
    return 0
  else
    err "转换没产出文件"
    rm -f "$src"
    return 1
  fi
}

VERIFY_OK=0
verify && VERIFY_OK=1

# ------------------------------------------------------------
#  总结
# ------------------------------------------------------------
hr
if [ "$VERIFY_OK" = 1 ]; then
  ok "全部就绪"
  say ""
  say "  下一步："
  say "    ./convert.sh <音频>     转换一个文件"
  say "    ./watch.sh              丢进 inbox/ 自动转"
  say "    ./convert.sh --status   看状态和进度"
  exit 0
else
  warn "还没完全好，检查上面的提示"
  say ""
  say "  常见问题："
  say "    · torch 报 cannot locate symbol → pkg upgrade -y（升级 libc++）"
  say "    · ffmpeg 报 libplacebo 符号错 → 同上"
  say "    · 卡在 Connecting to github.com → 换源或 apt-mark hold python-scipy"
  exit 1
fi
