# L99 for Mac

[Русский](README.ru.md) · [English](README.md) · 简体中文

[下载 Mac 安装包](https://github.com/AxiraDev/L99ForMac/releases/download/v0.10.1/L99-for-Mac-macOS-arm64.dmg) · [0.10.1 发布说明](https://github.com/AxiraDev/L99ForMac/releases/tag/v0.10.1) · [项目网站](https://axiradev.github.io/L99ForMac/zh/)

面向 **AULA L99** 的独立 macOS 配置应用，采用 Rust 协议核心和原生 SwiftUI 界面。**0.10.1** 采用 GNU GPLv3 许可证；0.10.0 新增英文、简体中文和自愿支持按钮。本项目与 AULA 无隶属关系。

下载并打开 `L99-for-Mac-macOS-arm64.dmg`，将 **L99 for Mac** 拖入 **Applications（应用程序）**。需要 Apple Silicon 和 macOS 14 或更高版本；系统音频可视化需要 **macOS 14.2 或更高版本**。运行应用无需安装 Rust 或 Python。

当前构建使用本地临时签名，没有 Developer ID 签名或 Apple 公证。如果 macOS 阻止首次启动，并且你信任下载来源，可在 **系统设置 → 隐私与安全性** 中选择仍要打开此应用。参见 [Apple 说明](https://support.apple.com/en-us/102445)。

请使用有线 USB 模式连接 L99。应用会先读取键盘设置，然后允许写入配置。本地更改会自动保存；点击“应用到键盘”才会写入。侧栏底部可切换语言。

- **按键映射：** 主层和 Fn 层、组合键、多媒体动作、禁用按键和宏映射。
- **宏：** 窗口内按键录制、组合键构建、按下和释放动作、延迟、重复次数及设备内存检查。
- **IPS 屏幕：** PNG/JPEG 相框和背景上传，最多 200 帧的 GIF，缩放、旋转和写入校验。上传后请在键盘上重新打开相应功能。
- **实时数据：** Mac 时间和日期、CPU/GPU 负载、可用的 CPU 温度，湿度固定为 0。实时更新时请保持应用运行。
- **音乐：** 系统音频驱动屏幕频谱和按键灯光。音频仅在本地处理，不会保存。
- **配置：** 自动保存和备份、JSON 导入导出及设置读回校验。

已在真实 L99 上确认相框、GIF、实时数据、随音乐变化的灯光、Play 控制，以及 F12/Fn+F12 宏。其他效果、设置、硬件版本和实际睡眠/断线恢复仍需更广泛测试。**暂不支持固件更新、2.4 GHz 配置和 Intel 构建。** 详见[验证记录](VERIFICATION.md)。

支持按钮会在浏览器中打开[开发者的 Boosty 页面](https://boosty.to/axira_dev/donate)。所有功能均免费；应用不会获取银行卡信息。参见[语言和捐赠配置](LOCALIZATION.md)。

## 从源码构建

安装 Rust、Xcode Command Line Tools 和用于检查及打包的 Python 3。在项目目录中运行：

```sh
python3 scripts/check_localization.py
bash scripts/build.sh
bash scripts/test_configuration.sh
bash scripts/test_audio.sh
python3 scripts/package.py
```

如需生成可拖入 Applications 的 DMG，请先安装仅构建时使用的 `ds-store==1.3.3` 和 `mac-alias==2.2.2`，再运行 `python3 scripts/package_dmg.py`。

源码包不含厂商二进制文件、固件、图像、翻译或反汇编代码，也不包含私人数据捕获或用户配置。参见[来源说明](PROVENANCE.md)和 [GNU GPLv3 许可证](LICENSE)。

## 许可证

Copyright (C) 2026 L99 for Mac contributors.

本程序是自由软件，采用 **GNU 通用公共许可证第 3 版（仅限第 3 版）**（`GPL-3.0-only`）。你可以按照该许可证使用、修改和分发本程序。本程序不提供任何担保。完整条款见 [LICENSE](LICENSE)。

发布应用的 DMG 或 ZIP 时，请同时提供同一版本的完整对应源代码及构建文件。在 GitHub 发布页将 `L99-for-Mac-source.zip` 与二进制文件一同提供，不另行收费。分发修改后的程序时，必须保留 GPLv3 条款并提供对应源代码。新条款不会撤销此前已按其他许可证分发副本所授予的权利。
