# Arch Linux 原生构建与发布方案

状态：Arch x86_64 原生包已在开发机编译、安装并做隔离 e2e；e2e 尚有失败，未接入发布。

## 目标与边界

- 继续在 Ubuntu 22.04 构建现有 `.deb`，保持它的 glibc 2.35 / Fcitx5 5.0.x 基线与原有发布门禁。Arch 的滚动环境不能取代这条链。
- 增加 **Arch 原生**构建：在 Arch 环境中编译 Rust 服务、Fcitx5 addon、设置程序，输出可直接由 pacman 安装的 `fcitx5-windinput-<版本>-<包修订>-x86_64.pkg.tar.zst`。
- 先交付 x86_64。aarch64 要在可用的 Arch Linux ARM 环境中原生构建并完成运行验证后再加，不能把 x86_64 上 `makepkg --ignorearch` 的成功当成运行验证。
- 现有 `fcitx5-windinput-bin` AUR 包是 Debian `.deb` 重打包。原生包验证通过后，让它消费 Arch 原生产物并保留包名；迁移前不提前宣称已摆脱 Debian ABI。

## 构建输入

1. `WindInput` 的同一 tag/commit；产品版本只取 `docs/VERSION`。`wind-setting` 与 `wind-ui-rust` 保持当前 CI 的兄弟目录布局，并固定到经过测试的 ref，记录三个源码 commit。设置程序仓不可读取时构建失败，不发缺失设置入口的半包。
2. 词库沿用 `linux-build.yml` 的单次生成结果，同一版本的 Debian/Arch 包消费同一个数据 artifact；保留 `gen-compat.sh linux`，禁止带入 Windows 的兼容规则。
3. 在 Arch 容器或原生 runner 里通过 pacman 安装 Rust、CMake/Ninja、Fcitx5 与 XCB/Wayland 开发依赖；按三个真实构建目标补齐设置程序依赖。记录 `pacman -Q` 快照以便复现滚动仓库版本。

## 新增构建链

- 已新增 `scripts/linux/package-arch.sh` 与 `scripts/linux/arch/PKGBUILD`：从本地三仓及 `build_dev/data` 构建。先用 `WIND_BUILD_LOCAL=1 ./scripts/dev.sh gd` 生成词库，再运行 `./scripts/linux/package-arch.sh`。CMake 指定 `CMAKE_INSTALL_LIBDIR=lib`，addon 安装到 `/usr/lib/fcitx5/libwindinput.so`；服务、设置、词库放 `/usr/lib/windinput/`，桌面文件、MIME、图标和 Fcitx5 描述文件安装到 `/usr/share/`。该本地 PKGBUILD 依赖脚本传入源码绝对路径，不可原样提交 AUR。
- 用 `makepkg` 生成标准 `.pkg.tar.zst`，按 Arch 的包依赖与可选依赖声明运行时组件；安装/升级/卸载脚本只处理包路径下的旧服务，提示用户重启 Fcitx5，不改用户配置，也不删除用户词库。`pkgver` 对应产品版本，预发布版本单独规范化为 pacman 可比较的版本后再发布，避免升级顺序错误。
- 已新增 `scripts/linux/verify-arch.sh` 并由本地打包入口调用：核对包元数据、三份 ELF 架构、文件清单、词库体积、Linux `compat.toml` 零规则、不可被组/其他用户写入、addon 链接 Wayland/Fcitx5、`ldd` 无缺库。仍需在干净 Arch 构建环境验证依赖声明的完整性。
- `scripts/linux/e2e.sh` 现可用 `WIND_E2E_SYSTEM_FCITX=1` 走系统 Fcitx5 / Xvfb / Python，原来的 Ubuntu SDK 路径仍是默认。开发机隔离 X11 e2e 实测 198/236 通过，38 项失败集中在菜单关闭后状态、Shift 模式、tooltip 等；不能作为发布通过。干净 Arch 桌面会话、Wayland 与升级后重载仍待验证。

### 2026-10-22 本机验证记录

- 环境：Arch 系发行版 x86_64，Fcitx5 5.1.23，Rust 1.94.0。当前源码有三处 Rust 不支持的 `if let` match guard，已在 `wind-coordinator/src/handle_temp.rs` 改为等价 guard + 取值，随后 `cargo fmt`。
- 原生 addon 使用系统 Fcitx5 头文件与 C++20、启用 Wayland；Rust 服务与设置程序均编译成功。`ctest` 13/13 通过。`makepkg` 输出 `fcitx5-windinput-0.127.0-1-x86_64.pkg.tar.zst`，共 207 个文件。
- 本机先卸载现有 `fcitx5-windinput-bin`，再 `pacman -U` 安装原生包并重装冒烟：`pacman -Qkk` 为 207 个文件、0 altered；三个 ELF 均为 x86-64，`ldd` 无缺库；`pacman -Qo /usr/lib/fcitx5/libwindinput.so` 归属新包。本机当前安装的是原生 `fcitx5-windinput`，没有自动恢复旧 AUR 包。未做卸载后用户数据验证。
- `scripts/linux/e2e.sh` 隔离 Xvfb / DBus 下 198/236。基础拼音上屏、候选窗、设置程序开启、服务重启与自愈均通过；菜单、模式状态和 tooltip 的失败需要回归分析。

## CI 与 AUR 接入顺序

1. 增加独立可调用的 `arch-build.yml`，以 Arch 原生容器构建 x86_64；手动触发时只上传 artifact，不改正式 Release。尽量复用 Debian 的词库 artifact，避免两个平台各自生成内容不同的词库。
2. 容器构建与安装冒烟、Fcitx5 e2e 均通过后，让 `release.yml` 把 Arch 构建列为发布硬依赖，在同一个 `publish` job 汇总 `.pkg.tar.zst` 与 `.sha256`。打包及验证失败时不创建缺 Arch 包的草稿；已发布版本补资产时避免重推旧 `latest*.json`。
3. 更新独立仓库的 `fcitx5-windinput-bin` PKGBUILD：下载 Arch 原生 Release 资产及固定 SHA-256，移除 `.deb` 解包和 multiarch 插件搬运；同步 `.SRCINFO`、`depends` 与 `.install`。当前 `.install` 还提到已删除的 `windinput-setup`，当前 `depends` 也含旧脚本专用的 `python`，须随迁移复核。**不要把 AUR 更新并入本仓提交**。
4. 完成正式包的升级实测后，再决定是否额外提供从公开源码本地编译的非 `-bin` AUR 包；设置程序源码与词库来源必须先能由普通用户独立取得，不能让 PKGBUILD 隐式依赖 CI 的私有凭据。

## 验收判据

Arch x86_64 干净环境下 `pacman -U` 可安装，`pacman -Qo /usr/lib/fcitx5/libwindinput.so` 指向本包；`ldd` 三个 ELF 无缺失库；真 Fcitx5 会话可输入、上屏、显示候选并打开设置；升级后重启 Fcitx5 加载新版 addon，卸载不删除用户数据。以上全部通过后才替换 AUR 的 Debian 重打包来源。
