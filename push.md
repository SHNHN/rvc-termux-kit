# 发布到 GitHub

## 零、先解决一个必踩的坑

Android 的 `/storage` 目录所有者不是你的 Linux 用户，git 会拒绝操作并报：

```
fatal: detected dubious ownership in repository at '...'
```

**必须先加一行例外**（只加一次，永久生效）：

```bash
git config --global --add safe.directory '*'
```

> 只放行这一条路径也行，把 `*` 换成你的项目绝对路径，更安全。

## 一次性准备

```bash
cd rvc-termux-kit
git init
git add .
git commit -m "feat: RVC Termux Kit - 手机端 RVC 批处理工具

- 纯本地推理，无网络依赖
- 相对路径，任意目录可放
- 自动检测架构/Python/内存
- 分块参数防低配 OOM
- 交互式引导 + 模型管理
- 完整中文文档与免责声明"
```

## 关联远程仓库

```bash
# 在 GitHub 上先建一个空仓库（不要勾选 README/gitignore）
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git branch -M main
git push -u origin main
```

## 推荐的仓库设置

**About 栏建议填：**

```
Android on-device RVC voice conversion. No root, no PC, no Ubuntu. Just Termux.
```

**Topics：**

```
rvc  voice-conversion  termux  android  audio  pytorch  ai-voice  self-hosted
```

## 发布前检查清单

先跑这一条，确认要传的东西里没有模型和音频：

```bash
git add -A
git ls-files | grep -E '\.pth$|\.wav$|\.mp3$|\.m4a$|engine/cli\.py' && echo "❌ 有不该传的文件！" || echo "✅ 干净"
```

正常应该是 **22 个文件、约 94KB**。


- [ ] `models/` 里没有任何 `.pth`（`ls models/` 只应有 `.gitkeep`）
- [ ] `engine/` 里没有上游源码（`ls engine/` 只应有 `.gitkeep`）
- [ ] `inbox/` `done/` `out/` 都是空的
- [ ] `.work/` 已被忽略
- [ ] 没有你的个人音频文件

```bash
# 一键核对
git status --short
du -sh .
```

正常情况下仓库应该只有 **200KB 左右**。

## 可选：加 LICENSE 徽章

在 README 开头加：

```markdown
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Termux-green.svg)
```
