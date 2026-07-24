# YouTube 更新与 Native VP9 修复手册

本文记录 `LOVAHE/uYouEnhanced` 当前已通过真机验证的 YouTube 构建方案，并提供下次更新 YouTube IPA 时可重复执行的检查流程。

## 当前已验证版本

| 组件 | 版本或提交 |
| --- | --- |
| YouTube | 21.21.3 |
| YouMod | 1.3.0 / `a130dbae9d7969ef44754c22d661a55a9e1d3086` |
| Tonwalter YTUHD | 1.13.4 / `cf266c2a351eb4f97e6bb2fb129509c501bdf207` |
| Native VP9 补丁 | `1.13.4+nativevp9.1` |
| YTVideoOverlay | 2.3.6 / `0f7dbc4387a0e38aad3180744e484fef6cbb9094` |
| pyzule-rw | `740d3716dcd98c20c000f12cdb88f1f0b2a533a4` |

构建入口：

- `.github/workflows/build-youmod.yml`
- `Tweaks/YTUHD-native-vp9-ios26.patch`

已验证构建：

- Action：<https://github.com/LOVAHE/uYouEnhanced/actions/runs/30081456878>
- 构建提交：`8db8260b060b121e57676d96e97143c262d33d8c`
- IPA SHA-256：`7a98a1b0486a891888e01b9fbf2f1626972aded791f7c3a07be0359093010462`

## 最终结构

最终 IPA 只注入：

1. YouMod
2. Tonwalter YTUHD
3. YTVideoOverlay

必须保留 `YTVideoOverlay`。YTUHD 的 `ReloadVideo.x` 在初始化时会加载 `YTVideoOverlay.dylib`，随后调用它提供的 `registerTweak:metadata:`。只编译 YTVideoOverlay 源码但不注入其 dylib，会留下启动期崩溃风险。

## Native VP9 补丁做了什么

YouTube 21.21.3 已不再包含 `HAMVPXVideoDecoder`。Tonwalter YTUHD 1.13.4 只通过这个类判断 VP9 是否存在，因此原版设置页只显示 `Use AV1`，不会进入正确的 VP9 配置路径。

补丁针对 iOS 26.2 及以上版本做两件事：

1. 在 YTUHD 初始化早期通过 `dlsym` 调用系统的 `VTRegisterSupplementalVideoDecoderIfAvailable`，注册 `vp09` decoder。
2. 在新版 iOS 上把系统原生 VP9 视为可用能力，使设置页显示 `Use VP9 and AV1` 与 Codec 选择。

补丁刻意不做以下操作：

- 不 hook YouTube 内部的 `SupportsCodec` 函数。
- 不静态修改 YouTube 主程序机器码。
- 不加入 libvpx 软件 VP9 decoder。
- 不加入 dav1d 软件 AV1 decoder。
- 不强制所有视频使用 VP9。

这样 H.264 仍可作为普通视频的候选格式，VP9 只在视频确实提供相应格式时参与选择。

## 已排除的失败方案

### PoomSmart YTUHD 2.6.0 直接注入

它包含软件 VP9/AV1 decoder、pattern 查找和函数 hook。当前 sideload 环境中出现过启动闪退，不作为稳定基线。

### VP9Compat 静态补丁

可以启动，也曾让直播显示 `vp09`，但普通点播会出现 `Something went wrong`，并且没有稳定解锁 4K。

### VP9Compat 启动期 inline hook

会在启动时直接闪退。不要恢复这条路线。

### 仅注入 Tonwalter YTUHD

可以启动，但缺少 YTVideoOverlay 时存在初始化崩溃风险；补齐依赖后仍只显示 `Use AV1`，无法解锁 VP9 4K。

## 下次更新 YouTube IPA

### 1. 只改 IPA 输入

先手动运行 `Build YouMod IPA` workflow，仅替换 `ipa_url`。保持以下源码提交不变，先判断新 YouTube 是否仍兼容：

- `YOUMOD_COMMIT`
- `YTUHD_COMMIT`
- `YT_VIDEO_OVERLAY_COMMIT`
- `Tweaks/YTUHD-native-vp9-ios26.patch`

不要同时升级所有组件，否则出现问题时无法判断是 YouTube 版本变化还是 tweak 变化。

### 2. 检查构建验证

workflow 必须继续验证：

- IPA ZIP 完整。
- `YouMod.dylib`、`YTUHD.dylib`、`YTVideoOverlay.dylib` 均存在。
- 三个资源 bundle 均存在。
- IPA 中没有 `.appex` 与 `PlugIns`。
- 没有 `VP9Compat`、uYou 或 uYouEnhanced 遗留 dylib。
- YouTube 主程序的 VP9 能力分支未被静态修改。
- YTUHD 包含系统 VP9 注册符号。
- YTUHD 不包含 `SupportsCodec`、libundirect、libvpx 或 dav1d decoder。

如果 YouTube 内部的校验字节发生变化，先分析新二进制，不能直接删除校验。

### 3. 真机验证顺序

每次只签一个候选包，并按以下顺序测试：

1. 安装后直接启动，确认没有启动闪退。
2. 打开 YTUHD 设置，确认显示 `Use VP9 and AV1`，而不是只有 `Use AV1`。
3. 开启 `Use VP9 and AV1`。
4. Codec 选择 `VP9`。
5. 保持“修复播放问题”关闭。
6. 保持“禁用 HDR”关闭。
7. 关闭低电量模式并重启 YouTube。
8. 先测试普通 1080p 点播。
9. 再测试已知提供 2160p 的普通点播。
10. 最后测试 4K HDR 与直播。

直播最高只有 1080p 不一定是故障；直播源可能本身未提供更高分辨率。判断 4K 是否正常应优先使用确认存在 2160p VP9 的普通点播视频。

### 4. 新版失效时的定位顺序

1. 检查 `VTRegisterSupplementalVideoDecoderIfAvailable` 是否仍存在于 YouTube 主程序或系统 VideoToolbox。
2. 检查 `HAMVPXVideoDecoder` 是否重新出现。
3. 检查 `MLHAMPlayerItem`、`MLABRPolicy`、`HAMDefaultABRPolicy` 与 `YTIHamplayerStreamFilter` 是否仍存在。
4. 检查 YTUHD 当前 hook 的 selector 是否仍存在于新 YouTube。
5. 检查格式列表中是否已经包含 1440p/2160p VP9，只是 UI 未显示。
6. 检查是否为服务器端账号实验或特定视频没有 VP9 编码。

只有确认系统原生 VP9 路径消失后，才重新评估软件 decoder；不要先恢复 pattern hook 或强制 `SupportsCodec`。

## 发布要求

- 正式 workflow 保持 `workflow_dispatch` 手动触发。
- 为临时远程构建加入的 `push` trigger，构建启动后必须立即移除。
- 所有依赖使用固定提交，不跟随 `main`。
- 发布时记录 Action URL、IPA 文件名和 SHA-256。
- 保留最后一个真机确认可用的 IPA，直到新版本完成全部验证。
