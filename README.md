# ✨ Mihomo Lite - 一键配置脚本 V1.8.1
<!-- GitHub Badges -->
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%2B-orange?logo=ubuntu)
![Debian](https://img.shields.io/badge/Debian-12%2B-red?logo=debian)
![Alpine](https://img.shields.io/badge/Alpine-Supported-blue?logo=alpinelinux)
![License](https://img.shields.io/badge/License-MIT-green)

> 🚀 **专为 VPS 打造的极简 Mihomo 管理工具。**
> 
> 安装后仅需在命令行输入 `mh`，即可唤出交互式管理面板。轻松实现内核安装、节点生成、订阅聚合与服务运维。

⚠️ **免责声明**：请务必在遵守当地法律法规、服务商条款（TOS）和网络使用政策的前提下使用本项目。

---

## ⚡ 快速安装

请在具有 `root` 权限的终端中执行以下一键安装命令：

```sh
curl -fsSL https://raw.githubusercontent.com/oKafuChino/Mihomo-lite/main/install.sh | sudo sh
```

安装完成后输入 `mh` 打开菜单，再选择 `4` 安装 / 更新 Mihomo 内核。

---

## 🌟 核心功能

通过终端输入 `mh` 即可打开 TUI 菜单，支持以下快捷操作：

* **📦 核心管理**：一键安装 / 卸载 Mihomo 内核至系统目录。
* **🔗 节点生成**：一键生成代理节点，并自动输出可复制导入的节点链接。
* **📊 节点管理**：查看所有已建节点、单节点链接以及 **Base64 聚合订阅**，支持单节点删除、一键清空和批量重命名。
* **⚙️ 服务运维**：一键查看 YAML 配置文件、重启服务进程。
* **🚀 性能优化**：支持运行时参数调优、sysctl 网络优化和公网 IP 本地缓存。
* **🌐 IPv6 支持**：支持开启 IPv6 监听、IPv6 DNS 解析和 IPv6 节点分享地址。
* **👥 多用户管理**：可在初次安装 Mihomo 内核时选择安装，支持用户增删、启停、到期时间、独立流量配额和手动流量统计。
* **📡 运行监控**：实时查看 Mihomo 运行日志。
* **🔄 无缝升级**：支持一键拉取并更新管理脚本自身。

### 🛡️ 支持的代理协议

生成节点功能目前内置了以下主流且高效的协议组合：

1.  **VLESS + Reality** 
2.  **Hysteria2**（上下行固定为 10Gbps）
3.  **AnyTLS**
4.  **VLESS + WebSocket**

菜单输入 `22` 可批量生成 Reality + Hysteria2 + AnyTLS，默认 SNI 为 `www.amd.com`，自动避开已存在的节点名和端口，并在最后统一重启服务。

菜单输入 `33` 可批量重命名所有节点，格式为 `国家旗帜Emoji国家全称-服务商名称-节点协议`，国家旗帜会根据输入的国家自动识别。

菜单输入 `44` 可调整 Mihomo 的 `GOMEMLIMIT` 和 `GOGC`，支持低配稳定、系统推荐、高吞吐和自定义参数。

菜单输入 `55` 可尝试应用 sysctl 网络优化，包括 BBR、队列、TCP/UDP 缓冲和本地端口范围。LXC 容器可能无法写入部分参数，脚本会自动跳过无权限项目。

菜单输入 `66` 可配置 IPv6 支持：关闭 IPv6、开启 IPv6 监听但继续分享 IPv4、开启并优先分享 IPv6、手动指定分享 IP 或刷新公网 IP 缓存。

如果初次安装 Mihomo 内核时选择启用多用户管理，菜单会显示 `77`。进入后可添加、查看、删除、启用/禁用用户，设置到期时间和流量配额，并手动刷新用户流量统计；未启用时不会显示该入口，也不会创建多用户数据库。

---

## 📂 目录与服务架构

本脚本在 Debian / Ubuntu 系统上会自动创建并守护 `systemd` 服务，在 Alpine 系统上则会创建 `OpenRC` 服务。核心路径分布如下：

| 组件名称 | 对应路径 | 说明 |
| :--- | :--- | :--- |
| **管理面板命令** | `/usr/local/bin/mh` | 终端快捷启动命令 |
| **Mihomo 内核** | `/usr/local/bin/mihomo` | 核心可执行文件 |
| **配置主目录** | `/etc/mihomo/` | 存储运行所需的各项配置 |
| **主配置文件** | `/etc/mihomo/config.yaml` | Mihomo 运行的源配置 |
| **节点数据库** | `/etc/mihomo/nodes.db` | 本地化存储已生成的节点记录 |
| **用户数据库** | `/etc/mihomo/users.db` | 仅启用多用户管理时创建 |
| **流量快照** | `/etc/mihomo/traffic.db` | 记录活跃连接的上次统计快照 |
| **功能开关** | `/etc/mihomo/features.env` | 记录是否启用多用户管理 |
| **运行参数** | `/etc/mihomo/runtime.env` | 存储 `GOMEMLIMIT` 与 `GOGC` |
| **网络参数** | `/etc/mihomo/network.env` | 存储 IPv6 开关和分享地址偏好 |
| **公网 IP 缓存** | `/etc/mihomo/public.ip` | 缓存 IPv4 / IPv6 分享地址，减少外部 API 请求 |
| **日志目录** | `/var/log/mihomo/` | 存储服务的运行与连接日志 |

*💡 后台守护服务名称：`mihomo`*

### 🧩 低配 LXC 容器说明

脚本默认使用兼顾稳定性和吞吐的 Mihomo 运行参数，降低 Alpine/LXC 小内存环境在高速率下崩溃或断流的概率：

* 默认关闭 `fake-ip` 缓存，DNS 使用 `redir-host`。
* 默认日志级别为 `warning`，减少高流量时的日志开销。
* 执行 `mh install` 时会提示填写 `GOMEMLIMIT` 和 `GOGC`。
* 后续可通过菜单 `44` 随时切换运行时性能档位。
* 菜单 `55` 可尝试应用网络栈优化；容器无权限的 sysctl 项会被跳过。
* Alpine 推荐 `192MiB/75`，Debian / Ubuntu 推荐 `384MiB/150`，直接回车即可采用推荐值。

也可以通过环境变量直接指定并重写服务：

```sh
MIHOMO_GOMEMLIMIT=384MiB MIHOMO_GOGC=150 mh install
```

如果容器内存极低并且仍然崩溃，可再收紧到 `128MiB/50` 或 `192MiB/75`。

节点链接里的公网 IP 会缓存到 `/etc/mihomo/public.ip`。如果 VPS 更换了出口 IP，删除该文件后重新查看或生成节点即可刷新。

### 🌐 IPv6 使用说明

默认保持 IPv4 兼容模式。需要 IPv6 时，在菜单输入 `66` 开启：

* 选择 `2`：Mihomo 监听 IPv6，节点分享链接仍优先使用 IPv4。
* 选择 `3`：Mihomo 监听 IPv6，节点分享链接优先使用 IPv6，链接中的 IPv6 地址会自动添加方括号。
* 选择 `4`：手动写入分享 IP，适合 VPS 有多个 IPv6 或自动识别不准确的情况。

开启 IPv6 后请确认 VPS、LXC 宿主机、防火墙和云厂商安全组均已放行对应端口的 IPv6 入站流量。

### 👥 多用户管理说明

多用户管理只能在首次执行 `mh install` 安装 Mihomo 内核时选择是否启用。未启用时，主菜单不会显示 `77`，也不会创建 `/etc/mihomo/users.db`。

启用后，用户会绑定到已有节点。脚本会把未过期、未禁用且未超出流量配额的用户写入对应 listener 的 `users` 配置中：

* VLESS + Reality / VLESS + WebSocket：为用户生成独立 UUID。
* Hysteria2 / AnyTLS：为用户生成独立密码。
* 到期、禁用和超出流量配额的用户会在重新渲染配置时自动从 Mihomo 配置中排除。
* 菜单 `77` -> `8` 可通过 Mihomo `external-controller` 的 `/connections` 接口刷新用户流量统计，也可执行 `mh traffic`。
* 第一次刷新会建立 `/etc/mihomo/traffic.db` 快照；后续刷新会按同一连接的上传 + 下载增量累加到用户 `used_bytes`。
* 统计逻辑会优先按用户名匹配，也会尝试按用户 UUID / 密码匹配；若当前 Mihomo API 没有返回可识别字段，脚本不会按端口聚合流量，因为同一端口下无法精确区分每个用户。
* 手动刷新只能统计两次刷新之间仍存在于 `/connections` 的活跃连接增量；如果需要更接近实时的配额控制，可以用 cron 定时执行 `mh traffic`。
* 菜单 `77` -> `9` 可重置指定用户的已用流量，便于测试配额。
