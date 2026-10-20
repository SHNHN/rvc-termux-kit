# RVC Termux Kit

在 Android 手机的 Termux 里跑 RVC 音色转换 —— 不需要 root，不需要电脑，不需要 Ubuntu。

一套纯本地的批处理工具：把歌丢进去，出来就是换好音色的成品。

```
inbox/  歌.mp3  ──►  convert.sh  ──►  out/  歌_模型名.wav
                                     │
out/    ──►  mix.sh 人声 伴奏  ──►  成品.wav
```

---

## 目录

- [它能做什么](#它能做什么)
- [准备工作](#准备工作)
- [安装](#安装)
- [下载音色模型](#下载音色模型)
- [下载基础模型](#下载基础模型)
- [引擎源码](#引擎源码)
- [快速开始](#快速开始)
- [命令参考](#命令参考)
- [配置说明](#配置说明)
- [低配手机调优](#低配手机调优)
- [常见问题](#常见问题)
- [工作原理](#工作原理)
- [性能参考](#性能参考)
- [免责声明](#免责声明)
- [致谢](#致谢)

---

## 它能做什么

RVC（Retrieval-based Voice Conversion）做的是**音色转换**，不是文字转语音：

| 输入 | 输出 |
|---|---|
| 一段人声录音 | 同样的唱法、节奏、语气，换成另一个人的音色 |

它**保留**原始的语气、节奏、颤音、咬字，只替换**音色**。所以：

- ✅ 适合：翻唱换音色、配音二创、声音玩具
- ❌ 不适合：从零生成歌声（那需要 TTS / 歌声合成，是另一类模型）
- ❌ 不支持：手机上没有 faiss，所以 `.index` 检索增强用不上（不影响正常转换）

---

## 准备工作

**你需要：**

- 一台 Android 手机（arm64，Android 8+）
- 至少 **4GB 空闲存储**、**4GB 内存**（6GB 以上体验更好）
- [Termux](https://f-droid.org/packages/com.termux/) —— **从 F-Droid 装，不要用 Google Play 版本**（Play 版已停止更新，包仓库是坏的）
- 一个 RVC v2 音色模型（`.pth`，见下文）

**第一次跑会下载约 500MB 依赖 + 350MB 基础模型。**

---

## 安装

```bash
# 1. 拉取本仓库
pkg install -y git
git clone <this-repo> rvc-termux-kit
cd rvc-termux-kit

# 2. 只做环境检测，看看缺什么（不装任何东西）
bash scripts/install.sh --check

# 3. 正式安装
bash scripts/install.sh
```

`install.sh` 会依次做：

1. **检测**：架构、Python 版本、内存大小，给出适合你机器的参数建议
2. **装系统包**：`python`、`ffmpeg`、`libsndfile`
3. **装 Python 依赖**：torch、numpy、scipy，以及 torch 启动必需的小包
4. **端到端验证**：造一段 2 秒测试音真的转一次，成功才报「全部就绪」

### 如果下载很慢

国内网络直接从 Termux 官方源拉包可能只有几十 KB/s。先换源：

```bash
termux-change-repo
```

选 `Mirror group` → 然后选 **TUNA（清华）** 或 **USTC（中科大）** 或 **上海交大**。

---

## 下载音色模型

> **这是唯一必须你自己准备的资源。**
> 本仓库出于版权与合规考虑，不附带任何模型。

音色模型（`.pth`）是**别人训练好的声音**，本仓库不附带任何模型 —— 它属于第三方资源，请自行下载并遵守原作者的使用条款。

### 推荐站点

| 站点 | 说明 |
|---|---|
| **[voice-models.com](https://voice-models.com/)** | 目前最大的 RVC 模型库之一，免费，可直接搜索角色名下载 |
| [Hugging Face](https://huggingface.co/models?search=rvc) | 搜 `rvc`，很多作者会传在这里 |
| [AI Hub Discord](https://discord.gg/aihub) | 社区分享，需要进 Discord |
| 百度贴吧「rvc吧」 | 中文社区，有教程和分享 |

### 怎么挑

在 [voice-models.com](https://voice-models.com/) 上，每个模型卡片会标注：

```
RVC v2 · RMVPE · 300 Epochs
```

- **RVC v2** ← 本工具只支持 v2。看到 v1 就别下了
- **RMVPE** ← 音高提取器，本工具默认就用它
- **Epochs** ← 训练轮数，一般 200~500 之间，太小会不像

### 下载后怎么装

**方式 A：自动（推荐）**

```bash
./models.sh install /storage/emulated/0/Download/xxx.pth
```

脚本会：
- 检查文件大小是否合理（30~80MB 才是正常的音色模型）
- 复制到 `models/`
- 如果同目录下有对应的 `.index`，一起拿过来
- 只有一个模型时自动设为当前模型

**方式 B：手动**

直接用文件管理器把 `.pth` 拷进 `models/` 目录，然后：

```bash
./models.sh use xxx.pth
```

### 切换模型

```bash
./models.sh list          # 看有哪些，● 是当前用的
./models.sh use yuuka     # 支持模糊匹配，不用写全名
./models.sh info yuuka    # 看采样率、f0、版本、训练轮数
```

---

## 下载基础模型

除了音色模型，RVC 还需要**两个公共基础模型**（约 350MB，所有音色共用）：

| 文件 | 大小 | 作用 |
|---|---|---|
| `hubert_base.pt` | ~181 MB | 内容特征提取（决定"说了什么"） |
| `rmvpe.pt` | ~173 MB | 音高提取（决定"唱什么调"） |

### 自动下载

```bash
./models.sh fetch-base
```

从 Hugging Face 拉取。如果下载失败（网络问题常见），用下面的手动方式。

### 手动下载

任选一个源：

- [Hugging Face · lj1995/VoiceConversionWebUI](https://huggingface.co/lj1995/VoiceConversionWebUI/tree/main)
- [RVC 官方 GitHub Releases](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/releases)

下载这两个文件，**文件名不要改**：

```
hubert_base.pt
rmvpe.pt
```

直接放进 `models/` 目录：

```bash
# 例如从手机的「下载」目录拷过来
cp /storage/emulated/0/Download/hubert_base.pt models/
cp /storage/emulated/0/Download/rmvpe.pt       models/

# 检查
./models.sh base
```

看到两个 ✓ 就齐了。

---

## 引擎源码

本仓库**不包含** RVC 推理引擎的源码 —— 它属于上游项目，按其许可证单独分发。你需要自己放进来：

```bash
cd rvc-termux-kit/engine

# 从上游拉取
git clone https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI.git upstream-tmp
```

然后从 `upstream-tmp/` 里把这几部分拷到 `engine/`：

```
engine/
├── infer.py                 推理入口（把上游 tools/rvc_for_realtime 或 infer-web 的逻辑整理成 CLI）
├── lib/                     模型定义：SynthesizerTrnMs768NSFsid 等
├── hubert/                  HuBERT 特征提取、fairseq 兼容层
└── rmvpe/                   RMVPE 音高提取
```

> **说明**：不同版本的 RVC 目录结构差异较大，`infer.py` 需要一个把「加载模型 → 提取 F0 → 提取特征 → 推理 → 输出」串起来的 CLI 入口。
> 这部分是从上游代码整合出来的胶水层，不含上游的模型权重。

放好后验证：

```bash
./rvc-kit doctor
```

看到 `✓ infer.py` 就对了。

---

## 快速开始

### 第一次用：跟着走一遍

```bash
bash setup.sh
```

交互式引导，会依次问：

1. Python 环境装了吗 → 没装就帮你装
2. 基础模型（hubert/rmvpe）有吗 → 没有就帮你下
3. 音色模型（.pth）有吗 → 没有会给你下载地址
4. 你的内存多大 → 建议合适的 `chunk` 值

全程大概 5 分钟（不含下载时间）。

### 之后

```bash
# 1. 自检，确认一切就绪
./rvc-kit doctor

# 2. 转换一个文件
./rvc-kit convert /storage/emulated/0/Download/我的歌.mp3

# 3. 或者：丢进 inbox/，让它自己转
cp /storage/emulated/0/Download/我的歌.mp3 inbox/
./rvc-kit watch

# 4. 看进度
./rvc-kit
```

### 完整流程示例

假设你要翻唱一首歌，手上有原曲和伴奏：

```bash
# 转换人声
./rvc-kit convert vocals.wav
#   → out/vocals_模型名.wav

# 和伴奏混起来（给参照人声，混出来响度才准）
./rvc-kit mix out/vocals_模型名.wav instrumental.wav \
              out/成品.wav vocals.wav

# 结果：out/成品.wav
```

如果没有单独的人声/伴奏，只有原曲：

```bash
# 先分离（相位相消法，商业歌曲效果较好）
./rvc-kit split 原曲.wav 伴奏.wav
```

---

## 命令参考

### `./rvc-kit` — 统一入口

| 命令 | 作用 |
|---|---|
| `./rvc-kit` | 看状态和进度 |
| `./rvc-kit convert <文件...>` | 转换（可多个） |
| `./rvc-kit watch` | 监听 `inbox/`，丢文件自动转 |
| `./rvc-kit models list` | 看已装模型 |
| `./rvc-kit mix 人声 伴奏 [输出] [参照] [dB]` | 混音 |
| `./rvc-kit split 原曲 输出伴奏` | 分离伴奏 |
| `./rvc-kit trim <文件>` | 剪掉尾部静音 |
| `./rvc-kit install` | 装环境 |
| `./rvc-kit doctor` | 自检排错 |

### `scripts/convert.sh`

```bash
./convert.sh --status              状态 + 分块进度 + 预计剩余时间
./convert.sh <文件>                转换单个
./convert.sh --all                 转 inbox/ 全部
```

进度长这样：

```
────────────── 转换中 ──────────────
  分块进度  [████████░░░░░░░░░░░░] 40%  (4/10)
  已用时间  18.2 分钟
  预计还需  27.3 分钟
```

### `scripts/models.sh`

```bash
./models.sh list                   列出音色模型 + 基础模型状态
./models.sh install <pth>          装入新模型
./models.sh use <名字>             切换当前模型
./models.sh base                   检查基础模型
./models.sh fetch-base             自动下载基础模型
./models.sh info <名字>            看模型详情
```

### `scripts/mix.sh`

```bash
./mix.sh <人声> <伴奏> [输出] [参照人声] [前推dB]
```

参数说明：

- **参照人声**（可选）：原始的人声轨。给了就按它的响度对齐，混出来整体响度跟原曲一致
- **前推 dB**（可选）：人声往前推多少，默认取 `config.ini` 的 `extra`

⚠ 人声是单声道时会自动复制成立体声再混，**不会把伴奏压成单声道**。

### `scripts/fmt.sh`

```bash
./fmt.sh to-wav <输入> [输出]      转标准 wav
./fmt.sh trim <输入> [余量秒]      智能剪掉尾部静音（谱分析判断，不是简单阈值）
./fmt.sh probe <输入>              看时长/采样率/声道
./fmt.sh loudness <输入>           看平均/峰值音量
```

### `scripts/watch.sh`

```bash
./watch.sh                         前台运行，Ctrl+C 退出
./watch.sh --daemon                后台运行
./watch.sh --stop                  停掉后台
./watch.sh --status                看它活着没
```

---

## 配置说明

全部在 `config/config.ini`，改完立即生效，不用重装。

### 模型

```ini
model = mymodel.pth      # models/ 里的文件名
speaker = 0              # 说话人 id，单角色模型填 0
```

### 音频

```ini
pitch = 0        # 变调半音：0=同音域，+12=男转女，-12=女转男，±1~5=微调
eq = 5           # 高频提亮 dB，0=关。RVC 输出齿音只剩源文件 1/3，不提亮会"咬字不清"
extra = 3        # 混音时人声前推 dB
```

**关于 `eq`**：这是最容易踩坑的参数。RVC 的内容特征只到 16kHz，输出的辅音/齿音细节比源文件少一大截，所以听起来「闷」「咬舌头」。提亮是唯一有效的补救手段：

| 值 | 效果 |
|---|---|
| 0 | 原始输出，明显发闷 |
| **5** | 推荐起点 |
| 8 | 更亮 |
| 11 | 接近原曲亮度，可能发刺 |

### 性能

```ini
threads = 4      # CPU 线程数
chunk = 4        # 分块大小（秒）—— 决定内存峰值
pad = 1.0        # 分块重叠秒数
```

---

## 低配手机调优

**内存是最容易 OOM 的地方。** 分块越大越快，但内存占用也线性上涨：

| 内存 | `chunk` | 预计峰值 | `threads` |
|---|---|---|---|
| 3~4 GB | **3** | ~2.0 GB | 3 |
| 6 GB | **4** | ~2.7 GB | 4 |
| 8 GB+ | 6~8 | 4~5 GB | 6 |

```bash
# 让工具自己给建议
./rvc-kit install --check
```

它会读 `/proc/meminfo` 并打印：

```
建议设置（按你的内存）
  chunk  4   （内存 6GB 对应的安全值）
  中配机器：threads 4，chunk 4（默认值可用）
```

**别为了快盲目调大 `chunk`** —— 被系统 OOM 杀掉会丢掉整首歌的进度。

### 其他提速手段

1. **插着充电器跑** —— 省电模式会降频
2. **关掉其他 app** —— 尤其大型游戏，抢内存
3. **别同时开多个转换** —— 工具会用锁文件拦住，但别硬绕
4. **`threads` 不要超过核心数** —— 超了会因为发热降频反而更慢

### 关于续航

转换时 CPU 满载，手机很烫是正常的。**建议拿掉手机壳、放在通风处**。

---

## 常见问题

### 命令找不到 / 脚本名带中文跑不了

本工具所有脚本都是**英文名**：`rvc-kit`、`convert.sh`、`watch.sh`、`models.sh`。

如果你之前用过别的 RVC 封装，`~/.bashrc` 里可能残留了指向旧路径的别名。清理一下：

```bash
grep -n "rvc\|conver\|watch" ~/.bashrc
# 找到后用编辑器删掉那几行，或直接重开一个 Termux 会话
```

### `cannot locate symbol "__hash_memory"` / `libplacebo.so`

torch 或 ffmpeg 的**动态库版本太旧**。修法：

```bash
pkg upgrade -y
```

这会把 `libc++`、`libplacebo` 一起升到和 torch/ffmpeg 匹配的版本。升级过程中如果问配置冲突，**按回车选 N**（保留现有配置），别选 Y。

### `ModuleNotFoundError: No module named 'typing_extensions'`

torch 装好了但缺启动依赖：

```bash
pip install --no-deps typing_extensions filelock fsspec jinja2
```

**注意 `--no-deps`**：不加的话 pip 会追着下 `sympy`（77MB），而推理根本用不到它。

### 卡在 `Connecting to github.com`

某个 apt 源的包重定向到了 GitHub，你的网络连不上。跳过它：

```bash
apt-mark hold python-scipy
pkg upgrade -y
```

### `Permission denied` 执行脚本

Android 的 `/storage` 分区是 **noexec**，不能直接 `./script.sh`。用 `bash` 解释执行：

```bash
bash scripts/install.sh      # ✅
./scripts/install.sh         # ❌ 报 Permission denied
```

### 转换时被系统杀掉 / 后台进程莫名退出

Android 12+ 有 **PhantomProcessKiller**，会限制后台子进程。打开这个开关：

**设置 → 开发者选项 → 最下面 →「停止限制子进程」→ 打开**

不打开的话，后台转换会被随机杀掉，还会报假的 `Permission denied`。重装 app 后需要重新打开。

### 转换成功但声音很闷 / 咬字不清

这是 RVC 的架构限制（内容特征只有 16kHz），不是 bug。提高 `eq`：

```ini
eq = 8      # 或 11
```

### 混音后变成单声道 / 伴奏没立体声了

`mix.sh` 已经处理了这个（人声复制成双声道再混）。如果你自己用 ffmpeg 手搓，注意 `amix` 遇到单声道输入会降维，要加 `pan=stereo|c0=c0|c1=c0`。

### 同一首歌转两次，结果文件 md5 不一样

**这是正常的。** RVC 的音色转换引擎本身有运行间浮动，同一份输入、同一套参数连跑两次，
输出的相关系数约 0.98、信噪比约 15 dB —— 听起来完全一样，但逐字节不同。

实测数据：

```
两次相同命令   SNR 14.9 dB   相关系数 0.984
```

所以：

- ❌ 不要用 `md5` 判断两次转换是否一致
- ✅ 用耳朵听，或者比 `ffmpeg -af volumedetect` 的响度
- ✅ 只有 **ffmpeg 后处理**（提亮、混音、剪裁）是逐字节确定的

### 模型装进去但 `models.sh list` 看不到

检查文件名后缀是不是 `.pth`，以及是不是真的 RVC 模型（不是下载失败的 HTML 页面）。用一个小的正常模型应该在 30~80MB。

```bash
./models.sh info <你的模型>
```

读不出元信息说明这多半不是 RVC 模型。

---

## 工作原理

```
源音频 (16k mono)
    │
    ├─► RMVPE ─────────────► F0 音高曲线
    │
    └─► HuBERT ────────────► 768 维内容特征（"说了什么"）
                │
                ▼
        说话人嵌入 emb_g[sid]（"谁在说"）
                │
                ▼
    ┌───────────────────────────┐
    │  enc_p → flow → dec       │  SynthesizerTrnMs768NSFsid
    └───────────────────────────┘
                │
                ▼
        40kHz / 48kHz 输出 ─► ffmpeg 提亮 ─► wav
```

关键点：

- **内容特征**由 HuBERT 提取，只有 16kHz 分辨率 → 输出的高频细节天然比原唱少
- **音高**由 RMVPE 单独提取，保留原唱的语调起伏
- **音色**来自 `emb_g` 说话人嵌入，这是换音色的核心
- 转换**保留时长和节奏**，所以成品和原曲天然对齐

---

## 性能参考

实测环境：Android 13，11GB RAM，8 核，Termux（无 GPU 加速）

| 音频长度 | 耗时 | 实时率 |
|---|---|---|
| 2.5 秒 | 46 秒 | 0.05x（模型加载占大头） |
| 60 秒 | ~12 分钟 | 0.08x |
| 103 秒 | ~35 分钟 | 0.05x |
| 187 秒 | ~65 分钟 | 0.06x |

**短音频的耗时主要花在加载 350MB 模型上**，长音频会摊薄这部分开销。

内存峰值：`chunk=4` 约 2.7GB。

> 想更快？只能在更高 `chunk` 和更高内存之间取舍，或者换台电脑跑。

---

## 免责声明

**使用本工具前请务必阅读并理解以下内容。**

### 1. 仅限合法用途

本工具是**技术工具**，用于音频处理研究、个人娱乐、内容创作。

使用者必须确保：

- 你拥有所处理音频的**合法使用权**（自己唱的歌、无版权伴奏、已获授权的素材）
- 你不侵犯任何人的**著作权、表演者权、录音录像制作者权**
- 你生成的音频不用于**商业发行、冒充他人、诈骗、诽谤**或其他违法用途

### 2. 关于"声音权"

**声音受法律保护。** 在中国《民法典》第 1023 条中，自然人的声音参照肖像权保护。其他国家也有类似规定。

这意味着：

- ❌ **不得**未经许可克隆他人声音并公开发布
- ❌ **不得**用他人音色制作歌曲、视频、配音并传播
- ❌ **不得**用于冒充他人身份进行任何活动
- ✅ 可以：用自己训练/自己声音的模型、用已获授权的模型做自己的创作

**许多平台（B站、抖音、YouTube 等）对 AI 换声内容有明确规则**，发布前请自行确认合规性。因违反平台规则导致的封号、限流，与本工具无关。

### 3. 模型版权归原作者

本仓库**不包含任何音色模型**。所有模型均由使用者自行从第三方站点下载。

- 模型的知识产权属于其**训练者/发布者**
- 使用前请阅读模型页面上的**使用条款**（很多模型明确禁止商用）
- 因使用第三方模型产生的纠纷，与本工具作者无关

### 4. 无担保

本软件按「现状」提供，**不提供任何明示或暗示的担保**，包括但不限于适销性、特定用途适用性和非侵权性的担保。

作者不对以下情况负责：

- 数据丢失、音频损坏、设备损坏
- 因使用本工具导致的任何直接的、间接的、偶然的、特殊的或后果性的损害
- 时间损失、收入损失、业务中断

**请务必保留原始音频的备份。**

### 5. 上游项目

本工具整合了以下开源项目的能力，请一并遵守其许可证：

- [Retrieval-based-Voice-Conversion-WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI) — MIT
- [HuBERT](https://github.com/facebookresearch/fairseq/tree/main/examples/hubert) — MIT
- [RMVPE](https://github.com/Dream-High/RMVPE) — 见其仓库
- [PyTorch](https://pytorch.org/) — BSD
- [ffmpeg](https://ffmpeg.org/) — LGPL/GPL

### 6. 接受条款

**使用本工具即表示你已阅读、理解并同意上述全部内容。**

如果你不同意其中任何一条，请立即停止使用并删除本工具。

---

## 致谢

- [RVC-Project](https://github.com/RVC-Project) — 音色转换核心算法与工具链
- [Termux](https://termux.dev/) — Android 上的 Linux 环境
- 所有开源模型的训练者和分享者

---

## 许可证

本仓库自身的脚本代码采用 MIT 许可证，详见 [LICENSE](LICENSE)。

**不包含**任何第三方模型权重、训练数据或上游引擎源码。
