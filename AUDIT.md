# 玩客云 OpenWrt 构建仓库审计

审计日期：2026-10-09。对象是 `86669666/openwrt-onecloud` 分支 `25.12`（与上游 `shiyu1314/openwrt-onecloud` 的 `25.12` 在审计开始时提交 `eb1dc90` 完全一致）。只读检查了本仓库全部脚本、工作流、补丁和默认配置，并核对了它们在构建时拉取的外部 Git 提交。没有把私钥内容写入本文。

分类只用四档：**确认后门**、**设计上有风险**、**过时且存在漏洞**、**正常**。没有在本仓库里找到隐藏的反弹 shell、混淆载荷或设备启动后主动外连的植入代码。下面的高危项是已公开的签名私钥、第三方软件源，以及明确写在脚本里的免密 root。

## 1. 更新结论

不能切到比 25.12 更新的 OpenWrt 发布分支。

- 2026-10-09 查询 `openwrt/openwrt` 的发布标签，最新的 25.12 标签是 [v25.12.5](https://github.com/openwrt/openwrt/releases/tag/v25.12.5)（2026-07-01 发布）。日历上更晚的 [v24.10.8](https://github.com/openwrt/openwrt/releases/tag/v24.10.8)（2026-07-26）属于上一个稳定分支，不是更新的大版本。
- 远程分支只有到 `openwrt-25.12` 为止的稳定分支，加上开发分支 `main` / `master`。没有 `openwrt-26.*`。
- `main` 同时带有 `target/linux/generic/kernel-6.12` 和 `kernel-6.18`。本仓库的通用补丁在 `patch/target/linux/generic/hack-6.12/`，玩客云板级树也只提供 `patches-6.12`。切到 `main` 不能和现有板级支持一起验证。
- 官方 OpenWrt 25.12 源码树里没有 `target/linux/amlogic` 或 meson8b / OneCloud。设备支持完全来自构建时克隆的外部仓库。

在 25.12 这条线上做了可以核对的前进：

| 项 | 审计前 | 现在 |
| --- | --- | --- |
| OpenWrt | 工作流用 `git tag \| tail -1` 浮动选择 `v25.*`。上游 2026-10-06 的 Actions 日志实际检出的是 v25.12.5，提交 `f0a60eee2f`，内核 6.12.94 | 固定 `openwrt-25.12` 的 `66673aad8f99e450f6ee2587254b1b2d19d45150`（2026-10-08）。比 v25.12.5 超前 251 个提交，内核 `target/linux/generic/kernel-6.12` 为 6.12.112 |
| 官方 feeds | v25.12.5 的 `feeds.conf.default` 有提交号；该分支 HEAD 改成了 `;openwrt-25.12` 浮动分支 | `sh/pins.env` 把 packages / luci / routing / telephony / video 固定到 2026-10-09 核对过的提交 |
| 第三方 Git | `master`、`openwrt-25.12`、`packages`、`porxy`、`26.x` 全是分支尖 | 同一文件里的完整提交号 |
| 板级树 | `shiyu1314/s805` 分支 `6.12`，用 `PERSONAL_ACCESS_TOKEN` 克隆。不带令牌时 GitHub 返回 404，仓库不在公开列表里 | 不再使用该私有仓库。板级文件来自公开仓库 [rmoyulong/OneCloud_OpenWrt](https://github.com/rmoyulong/OneCloud_OpenWrt) 提交 `ece61123be9f79107f5fd21448cdb8a10d8902b3` 的 `lede6.12/target/linux/amlogic`，并写入 `board/amlogic/` |

阻塞项：无法在不保存个人访问令牌的前提下获取 `shiyu1314/s805`。因此固件里的板级支持不是上游 Actions 正在使用的那份私有树，开机兼容性不能用上游 2026-10-06 的成功构建来保证。`board/amlogic/SOURCE.txt` 记录了来源。镜像配方里原来的 `onecloud` 不是已定义的 `Build/` 步骤，已从 `board/amlogic/image/Makefile` 去掉。

wolfSSL 5.9.4 在上述 OpenWrt 提交中合入，发行说明列出高危 [CVE-2026-93302](https://github.com/wolfSSL/wolfssl/releases/tag/v5.9.4-stable)、[CVE-2026-89102](https://github.com/wolfSSL/wolfssl/releases/tag/v5.9.4-stable)、[CVE-2026-89136](https://github.com/wolfSSL/wolfssl/releases/tag/v5.9.4-stable)。本仓库默认配置走 OpenSSL（`sh/op.sh` 第 70 行把 `libustream-mbedtls` 换成 `libustream-openssl`，`config/config-common` 选择 `wpad-openssl` 和 `nginx-ssl`），默认固件不包含 wolfSSL。内核从 6.12.94 升到 6.12.112 会进入默认固件。

## 2. 发现

### 设计上有风险

1. **已公开的 apk 签名私钥，且镜像信任同一把公钥。** 审计前 `patch/keys/private-key.pem` 是 EC P-256 私钥。`patch/keys/public-key.pem` 与 `files/etc/apk/keys/public-key.pem` 的公钥 DER SHA-256 都是 `dcf9a799fccae5e52ebd292502a656245bde1f9e7a891a24309c2588a4eda254`，与该私钥导出的公钥一致。设备会信任用这把钥匙签出的 apk。钥匙仍留在 git 历史里（本仓库禁止强推，不能改写历史）。本提交从工作树删除了私钥和预置公钥。
2. **默认 apk 源指向第三方主机。** 审计前 `files/etc/apk/repositories.d/distfeeds.list` 第 1–4 行是 `https://jkkk.cc.cd/arm_cortex-a5_neon-vfpv4/{base,kmod,luci,packages}/packages.adb`。2026-10-09 解析到 `66.33.60.129` 与 `76.76.21.93`，HTTP 响应为 Vercel，`packages.adb` 的 `last-modified` 为当天。这不是 `downloads.openwrt.org`。配合上一条，任何持有历史私钥的人都可以为这台设备制作可被信任的软件包，只要流量能到达该索引或攻击者能替换索引。已删除该文件，镜像改回构建系统生成的官方 feed。
3. **apk 索引用仓库内私钥签名，并强制推送到他人的 GitHub 仓库。** 审计前 `.github/workflows/apk.yml` 调用 `kmod-sign`，再把 `openwrt/bin/packages` `git push --force` 到 `github.com/shiyu1314/6.12`，令牌是 `secrets.PERSONAL_ACCESS_TOKEN`。`patch/keys/kmod-sign` 原来带 `--allow-untrusted` 和 `--sign $TOP/private-key.pem`。该仓库公开 API 返回 404。已停止签名和推送，改为上传本仓库的 Actions artifact。`kmod-sign` 现在要求环境变量 `APK_PRIVATE_KEY` 指向仓库外的钥匙，并且不再使用 `--allow-untrusted`（`patch/keys/kmod-sign` 第 7–10 行）。
4. **三个工作流用个人令牌克隆私有板级树。** URL 形如 `https://shiyu1314:${{ secrets.PERSONAL_ACCESS_TOKEN }}@github.com/shiyu1314/s805`。令牌会出现在进程参数里。已改为复制 `board/amlogic`（`.github/workflows/op.yml` 第 146 行，apk 与 toolchain 工作流同样处理）。
5. **ttyd 被改成免密 root。** 审计前 `sh/op.sh` 有 `sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config`。`login -f root` 在后来设置了 root 密码之后仍然跳过认证。固件工作流的默认插件列表包含 `luci-app-ttyd`。已删除这行 sed，并把 `CUSTOM_PLUGINS` 默认值改为空（`.github/workflows/op.yml` 第 35–38 行）。
6. **LuCI 上传安装绕过 apk 签名。** 已删除的 `patch/luci/0008-luci-app-package-manager-support-installing-uploaded.patch` 第 44 行把 `install-upload` 映射为 `apk add --allow-untrusted`。这是给管理界面用的，不是开机后门，但它明确关掉签名检查。补丁在新的 LuCI 提交上也无法完整应用。已删除，不再打这枚补丁。
7. **apk 版本与依赖名校验被丢掉。** 已删除的 `patch/apk-tools/999-hack-for-linux-pre-releases.patch` 让 `apk_version_validate()` 的失败不再返回错误，依赖解析失败时改为接受任意依赖名。对官方软件包不是必需的。已删除，工作流仅在目录里仍有补丁时才复制。
8. **构建输入直接拼进 shell。** 审计前 `op.yml` 把 `OP_IP`、`OP_rootfs`、`CUSTOM_PLUGINS` 写进 `run` 脚本。能触发 `workflow_dispatch` 的人可以注入命令。现改为环境变量，并限制 IP、分区大小和插件名字符（`.github/workflows/op.yml` 第 149–180 行）。
9. **第三方 Actions 与浮动的 `master` 文件。** `softprops/action-gh-release@v2.1.0`、`dev-drprasad/delete-older-releases@v0.3.4`、`Mattraks/delete-workflow-runs@v2.1.0` 原来只钉标签。`apk.yml` / `op.yml` 用 `curl -s` 把 `immortalwrt/immortalwrt` 的 `master` 上 `config/Config-kernel.in` 覆盖到 OpenWrt。`curl -s` 失败时会把错误页写进配置。已改为提交号 `305089f95180d4ab5206437b3527c7ed6cc46bc4`，并用 `curl -fsSL`（`sh/checkout-openwrt.sh`）。Actions 改为提交号。
10. **xcrypt 关闭 FORTIFY。** `sh/op.sh` 第 49 行给 `libxcrypt` 设置 `PKG_FORTIFY_SOURCE:=0`。这会降低该库的编译期加固。保留，避免改动后 xcrypt 编不过；默认固件不一定链接到有问题的路径，但设置本身是真实的。
11. **nginx 以 root 运行，并接受很大的请求体。** `patch/nginx/uci.conf.template` 第 8 行 `user root;`，第 29 行 `client_max_body_size 8192M;`。`sh/op.sh` 第 115 行把 nginx 的 stdout/stderr 从 procd 日志里关掉。Web 服务跑在 root 下，出漏洞时影响面是整机。没有改运行用户，避免 LuCI 起不来。
12. **root 没有密码。** `files/etc/passwd` 第 1 行是 `root:x:0:0:root:/root:/bin/bash`，仓库里没有 shadow 或密码哈希。OpenWrt 默认也是空密码，发布说明原来写「默认密码：无」。空密码加上监听 LAN 的 LuCI / SSH 时，同一局域网里的人可以登录。没有写入新密码。发布说明改为要求首次登录后设置密码。
13. **自定义 nft 脚本在防火墙启动时以 root 执行。** `patch/diy/100-openwrt-firewall4-add-custom-nft-command-support.patch` 让 `fw4` 调用 `/bin/sh /etc/firewall4.user`。镜像里的 `files/etc/firewall4.user` 只有注释「自定义规则」，没有放行端口。机制本身允许以后写入任意 nft 规则。
14. **第三方软件包整体替换官方 curl、nginx、golang、fstools、util-linux。** `sh/op.sh` 第 94–141 行。这些是供应链上最值得继续人工审计的部分。本次只固定了提交，没有逐行审计 nginx / golang 分支。默认 `config/config-common` 会编译 nginx 与 util-linux，不会默认编入 `porxy` 分支里的代理插件。
15. **`my-default-settings` 关掉 nginx 的本机限制，并改用国内 NTP。** 该包不在本仓库，而在 `shiyu1314/openwrt-feeds` 的 `packages` 分支，现固定为 `e717b77d3067c3a8ec68fa3045e7028ce49b3257`。`my-default-settings/files/zzz-default-settings` 把 `restrict_locally` 那一行注释掉，NTP 设为 `ntp.aliyun.com`、`time1.cloud.tencent.com`、`time.ustc.edu.cn`、`cn.pool.ntp.org`。没有发现回连作者服务器的 URL。OpenWrt 默认防火墙仍拒绝 WAN 入站，所以注释掉 `restrict_locally` 主要少了一层 LAN 绑定。`config/config-common` 第 1 行默认安装这个包。
16. **工作流日志被清空。** `Delete_Old_Workflow_Runs.yml` 原来 `retain_days: 0` 且 `keep_minimum_runs: 0`。已改为保留 30 天、至少 5 次（第 20 行附近）。
17. **固件工作流会删除旧 Release，只留最新 1 个。** `op.yml` 里 `delete-older-releases` 的 `keep_latest: 1`。不是后门，但会删掉已发布固件。保留该行为，只把 Action 钉到提交。

### 过时且存在漏洞

18. **浮动的 v25.12.5 基线落后于已审核的 25.12 分支。** 见第 1 节。内核 6.12.94 相对 6.12.112 少了约三个月的稳定补丁。wolfSSL 高危项只影响选择 wolfSSL 的构建。没有为「整个 6.12.94」编造一份 CVE 清单。
19. **GitHub Actions 使用 `ubuntu-22.04`。** 标准托管运行器上的系统包会过期，但固件本身不用这些宿主机库。未改运行器，避免和上游缓存路径分叉。

### 正常

20. **`files/root/1.sh`** 只在用户手动执行时用 `parted` / `resize2fs` 扩大 eMMC 分区，没有网络访问。
21. **`files/etc/uci-defaults/gen-mac-address`** 用 `/dev/urandom` 生成本地管理 MAC。`dhcp-lan` 把 LAN 改成 DHCP 客户端；默认工作流在 `ENABLE_DHCP` 不是 `true` 时删除它（`op.yml` 第 169–171 行）。
22. **`files/etc/profile.d/30-sysinfo.sh`** 只读本机负载、内存和网卡地址，没有外连。
23. **`files/etc/firewall4.user`** 没有放行端口。
24. **ImmortalWrt `automount` / `autosamba`**（提交 `305089f95180d4ab5206437b3527c7ed6cc46bc4`）的脚本里没有 URL、`curl` 或 `wget`。`sbwml/autocore-arm` 提交 `9b52f345ee2db331ce2fefcdcc50a9d6120c11a3` 的 `files/generic/090-autocore` 只在本地移动 LuCI 文件并重启 `rpcd`。
25. **板级 DTS** `board/amlogic/files/arch/arm/boot/dts/amlogic/meson8b-onecloud.dts` 是 Thunder OneCloud 的硬件描述，作者标记为 hzy。MMC 补丁 `patches-6.12/903-add-dts-and-identify-emmc.patch` 调整 HS200/HS400 时序，PWM 补丁只改占空比读回。没有网络或凭证。
26. **LuCI / firewall4 的其余补丁** 是界面、自定义 nft 文本和内核配置符号，不是下载器。`patch/target/linux/generic/hack-6.12/` 里一个补丁关掉 BTF 模块警告，另一个给 arm64 的 `/proc/cpuinfo` 加 model name；OneCloud 是 armv7，后者对本机无效果。

### 未逐行审计、因此不能标成「正常」的部分

`sh/op.sh` 仍会克隆 `sbwml` 的 nginx、curl、golang、fstools、util-linux、nghttp3、ngtcp2，以及 `shiyu1314/openwrt-feeds` 的 `packages` 与 `porxy` 两个提交。默认固件不启用 `porxy` 里的 `luci-app-momo` / `nikki` / `openclash`。这些树很大，本次没有做完整源码审计。它们被固定提交号，避免再跟着分支尖移动。

## 3. 本提交改了什么

- `sh/pins.env`、`sh/checkout-openwrt.sh`：OpenWrt、官方 feeds、ImmortalWrt 内核菜单固定到审核过的提交。
- `sh/op.sh`：所有 `git clone -b <分支>` 改为按提交号抓取；删除 ttyd 免密 root；作者字符串只保留字母数字；不再在打完本地补丁后执行第二次 `feeds update`（那会把补丁冲掉）。
- 删除 apk 私钥、预置公钥、`jkkk.cc.cd` 软件源、apk 版本校验补丁、LuCI `--allow-untrusted` 补丁。
- `board/amlogic/`：公开的 6.12 OneCloud 板级树，替代私有 `s805` 克隆。
- 三个固件/工具链工作流不再使用 `PERSONAL_ACCESS_TOKEN`，不再推送到 `shiyu1314/6.12`。apk 工作流只上传 artifact。
- Rust 的 `--ci false` 补丁按当前 `lang/rust/Makefile` 重放，否则 `sh/op.sh` 会在打补丁时退出。默认配置不编译 Rust。

没有加入密钥，没有推送到 `shiyu1314/openwrt-onecloud`，没有改写历史。

## 4. 构建结果

本节在固件编译结束后更新。目标是 OneCloud（`CONFIG_TARGET_amlogic_meson8b_DEVICE_thunder-onecloud`），配置为 `config/config-common`，不附加默认第三方插件。
