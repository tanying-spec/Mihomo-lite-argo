# ✨ Mihomo Lite - 一键配置脚本 V1.12.2（Argo 稳定版）
<!-- GitHub Badges -->
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%2B-orange?logo=ubuntu)
![Debian](https://img.shields.io/badge/Debian-12%2B-red?logo=debian)
![Alpine](https://img.shields.io/badge/Alpine-Supported-blue?logo=alpinelinux)
![License](https://img.shields.io/badge/License-MIT-green)

> 🚀 **专为 VPS 打造的极简 Mihomo 管理工具。**
>
> 安装后仅需在命令行输入 `mh`，即可唤出交互式管理面板。轻松实现内核安装、节点生成、订阅聚合与服务运维。

**原作者：** [oKafuChino](https://github.com/oKafuChino)

**Argo 集成与优化：** [TANYING](https://github.com/tanying-spec)

⚠️ **免责声明**：请务必在遵守当地法律法规、服务商条款（TOS）和网络使用政策的前提下使用本项目。

---

## ⚡ 快速安装

请在具有 `root` 权限的终端中执行以下一键安装命令：

```sh
curl -fsSL https://raw.githubusercontent.com/tanying-spec/Mihomo-lite-argo/main/install.sh | sudo sh
```

安装完成后输入 `mh` 打开菜单，再选择 `4` 安装 / 更新 Mihomo 内核。

---

## 🌟 核心功能

通过终端输入 `mh` 即可打开 TUI 菜单，支持以下快捷操作：

* **📦 核心管理**：一键安装 / 更新 / 卸载 Mihomo 内核，更新失败自动恢复。
* **🔗 节点生成**：一键生成代理节点，并自动输出可复制导入的节点链接。
* **📊 节点管理**：查看所有已建节点、单节点链接以及 **Base64 聚合订阅**，支持节点名称、监听端口、凭据和 WebSocket 模式编辑，也支持单节点删除、一键清空和批量重命名。
* **⚙️ 服务运维**：一键查看 YAML 配置文件、重启服务进程。
* **🚀 性能优化**：支持运行时参数调优、省资源稳连模式、高吞吐/跑满带宽模式、sysctl 网络优化和公网 IP 本地缓存。
* **🌐 IPv6 支持**：支持开启 IPv6 监听、IPv6 DNS 解析和 IPv6 节点分享地址。
* **👥 多用户管理**：可在初次安装 Mihomo 内核时选择安装，支持用户独立端口、增删启停、到期时间、独立流量配额、手动/自动流量统计和用户专属订阅分发。
* **📡 运行监控**：实时查看 Mihomo 运行日志。
* **🛡️ 稳定与回滚**：配置写入前执行 Mihomo 自检，服务失败自动恢复旧配置；内核、cloudflared 和管理脚本均可回滚上一版本。
* **🧱 状态事务**：节点、多用户、运行参数、网络设置和功能开关的重要修改使用快照、并发锁和中断恢复，失败不会留下半写入状态。
* **🔌 端口检查**：同时检查节点数据库、用户数据库和系统真实 TCP/UDP 监听端口。
* **🔐 下载校验**：优先验证上游 SHA-256 sidecar；上游未提供时继续执行格式、语法和可执行性检查。
* **🧹 日志保护**：安装时配置日志轮转，单文件达到 10MiB 后轮转压缩并保留 3 份。
* **🧯 压力恢复**：Tunnel 重启会修复服务模板、检查本地 Mihomo 源站并等待边缘连接恢复；菜单 `88` 提供 OOM、内存、进程和日志诊断。
* **♻️ 自动恢复**：固定 Tunnel 安装后自动启用轻量健康守护；每分钟检查进程、本地 WS 源站和边缘连接，连续异常2次才修复，并设置5分钟冷却避免重启风暴。
* **🔄 无缝升级**：支持一键更新 Mihomo、cloudflared 与管理脚本，菜单 `10` 提供版本回滚。
* **🩺 健康检查**：菜单 `11` 或命令 `mh doctor` 检查配置、服务、数据库、监听端口、Tunnel 连接和 Token 权限。
* **☁️ Argo Tunnel**：节点统一从菜单 `1` 创建；菜单 `88` 仅负责固定 Tunnel 的安装、更新、状态、检测、回滚和卸载。Token 使用 `--token-file` 读取。

### ☁️ Argo / Cloudflare Tunnel

安装管理脚本后输入 `mh`：

1. 选择 `4` 安装 Mihomo。
2. 选择 `88` → `1`，粘贴 Cloudflare 固定 Tunnel Token；Token 仅保存在 `/etc/cloudflared/token`（权限 `600`），cloudflared 通过 `--token-file` 读取。
3. 选择主菜单 `1` → `VLESS + WebSocket` → `Cloudflare Tunnel / Argo` 创建节点；填写 Tunnel 公共主机名和可选的 CF 优选 IP/域名，listener 只绑定 `127.0.0.1`。
4. 在 Cloudflare Tunnel 后台添加公共主机名，服务填写脚本显示的 `http://127.0.0.1:<VLESS-WS 本地端口>`。
5. 使用菜单 `88` → `3/4` 执行本地和公网检测，二者都应返回 `HTTP/1.1 101 Switching Protocols`。

客户端使用该公共主机名的 `443` 端口、TLS，以及相同的 WebSocket Host 和 Path。Tunnel 主动向 Cloudflare 建立出站连接，因此 WS 本地端口无需 NAT 映射，也不需要 DDNS。卸载 Argo 不会删除 Mihomo 或节点配置。

多线程测速会同时增加 WebSocket 连接数、文件描述符和内存缓冲。脚本为 cloudflared 设置 `262144` 文件描述符上限，并根据容器内存设置 Go 内存目标；低内存 LXC 仍建议使用菜单 `44` 的省资源稳连模式并控制测速线程数。如果节点突然不可用，可进入菜单 `88` 重启 Tunnel；该操作会先检查本地 Mihomo 源站，并在失败时联动恢复。菜单 `88` 的压力诊断可检查 cgroup OOM 计数和最近服务日志。

Tunnel 自动恢复默认随固定隧道安装或手动重启启用，也可在菜单 `88` 中开关。进程退出时仍由 Systemd/OpenRC 立即拉起；健康守护用于处理“进程仍在但边缘连接为0”或“本地 Mihomo WS 源站失效”的半失效状态。恢复记录写入 `/var/log/mihomo/tunnel-watchdog.log`。

> **重要：Argo 公共主机名不要提前创建 A/AAAA 记录。** 在 Tunnel 路由中保存公共主机名后，Cloudflare 会自动创建指向 `*.cfargotunnel.com` 的 CNAME。若已存在同名 A/AAAA，请先删除冲突记录。

### VLESS-WS 三种模式

| 模式 | 是否输入域名 | 本地监听 | NAT 映射 | DNS 要点 |
| :--- | :--- | :--- | :--- | :--- |
| IP 直连 WS | 否 | 公网监听 | 需要 | 使用公网 IP 和映射端口 |
| Cloudflare CDN WS-TLS | 是 | 公网监听 | 需要，且入口端口需受 Cloudflare 支持 | 创建代理 DNS 记录指向公网 IP |
| Argo Tunnel WS-TLS | 是（Tunnel 公共主机名） | `127.0.0.1` | 不需要 | 不预建 A/AAAA，由 Tunnel 自动创建 CNAME |

脚本生成 Argo 链接时会自动使用入口 `443`、`security=tls`、正确的 `sni`、`host` 和 WebSocket `path`；可另填 Cloudflare 优选域名/IP 作为客户端入口，但 SNI/Host 始终保持 Tunnel 公共主机名。

### 🛡️ 支持的代理协议

生成节点功能目前内置了以下主流且高效的协议组合：

1.  **VLESS + Reality** 
2.  **Hysteria2**（上下行固定为 10Gbps）
3.  **AnyTLS**
4.  **VLESS + WebSocket**

菜单输入 `22` 可批量生成 Reality + Hysteria2 + AnyTLS，默认 SNI 为 `www.amd.com`，自动避开已存在的节点名和端口，并在最后统一重启服务。

菜单输入 `33` 可批量重命名所有节点，格式为 `国家旗帜Emoji国家全称-服务商名称-节点协议`，国家旗帜会根据输入的国家自动识别。

菜单输入 `44` 可调整 Mihomo 的 `GOMEMLIMIT`、`GOGC` 和 `GOMAXPROCS`，支持省资源稳连、系统推荐、高吞吐/跑满带宽和自定义参数。

菜单输入 `55` 可尝试应用 sysctl 网络优化，包括 BBR、队列、TCP/UDP 缓冲和本地端口范围。LXC 容器可能无法写入部分参数，脚本会自动跳过无权限项目。

菜单输入 `66` 可配置 IPv6 支持：关闭 IPv6、开启 IPv6 监听但继续分享 IPv4、开启并优先分享 IPv6、手动指定分享 IP 或刷新公网 IP 缓存。

如果初次安装 Mihomo 内核时选择启用多用户管理，菜单会显示 `77`。进入后可添加、查看、删除、启用/禁用用户，设置到期时间和流量配额，手动刷新用户流量统计，开启每 10 分钟自动刷新，并分发用户专属订阅；未启用时不会显示该入口，也不会创建多用户数据库。

---

## 📂 目录与服务架构

本脚本在 Debian / Ubuntu 系统上会自动创建并守护 `systemd` 服务，在 Alpine 系统上则会创建 `OpenRC` 服务。核心路径分布如下：

| 组件名称 | 对应路径 | 说明 |
| :--- | :--- | :--- |
| **管理面板命令** | `/usr/local/bin/mh` | 终端快捷启动命令 |
| **Mihomo 内核** | `/usr/local/bin/mihomo` | 核心可执行文件 |
| **Mihomo 上一版本** | `/usr/local/bin/mihomo.previous` | 菜单 `10` 回滚使用 |
| **配置主目录** | `/etc/mihomo/` | 存储运行所需的各项配置 |
| **主配置文件** | `/etc/mihomo/config.yaml` | Mihomo 运行的源配置 |
| **节点数据库** | `/etc/mihomo/nodes.db` | 本地化存储已生成的节点记录 |
| **用户数据库** | `/etc/mihomo/users.db` | 仅启用多用户管理时创建 |
| **流量快照** | `/etc/mihomo/traffic.db` | 记录活跃连接的上次统计快照 |
| **流量规则版本** | `/etc/mihomo/traffic-rules.version` | 标记当前 iptables 统计规则格式，升级后自动重建旧规则 |
| **自动刷新任务** | root crontab | 仅启用自动流量刷新时写入 |
| **功能开关** | `/etc/mihomo/features.env` | 记录是否启用多用户管理 |
| **运行参数** | `/etc/mihomo/runtime.env` | 存储 `GOMEMLIMIT`、`GOGC`、`GOMAXPROCS` 与 `GODEBUG` |
| **网络参数** | `/etc/mihomo/network.env` | 存储 IPv6 开关和分享地址偏好 |
| **公网 IP 缓存** | `/etc/mihomo/public.ip` | 缓存 IPv4 / IPv6 分享地址，默认 6 小时自动过期 |
| **cloudflared Token** | `/etc/cloudflared/token` | 固定隧道 Token，权限 `600` |
| **cloudflared 内部监控** | `127.0.0.1:20241` | 仅供脚本读取 Tunnel 状态，不需要开放或映射 |
| **日志目录** | `/var/log/mihomo/` | 存储服务的运行与连接日志 |

*💡 后台守护服务名称：`mihomo`*

### 🧩 低配 LXC 容器说明

脚本默认使用兼顾稳定性和吞吐的 Mihomo 运行参数，降低 Alpine/LXC 小内存环境在高速率下崩溃或断流的概率：

* 默认关闭 `fake-ip` 缓存，DNS 使用 `redir-host`。
* 默认日志级别为 `warning`，减少高流量时的日志开销。
* 执行 `mh install` 时会提示填写 `GOMEMLIMIT`、`GOGC` 和 `GOMAXPROCS`，并自动写入 `GODEBUG=madvdontneed=1` 以降低 Go 运行时长期保留的 RSS。
* `GOMEMLIMIT` 会优先按 cgroup v2/v1 硬内存限制生成推荐值，给系统、TLS/QUIC 缓冲和内核网络缓冲预留余量；不会把 `memory.high` 或可能显示宿主机内存的 `/proc/meminfo` 当作容器限制。
* 推荐档默认使用更高的 `GOGC`，在 `GOMEMLIMIT` 兜底下减少 Go GC 频率，降低高速率下的 CPU 开销。
* `GOMAXPROCS` 会优先按 cgroup CPU 配额推荐，避免 LXC 容器误用宿主机 CPU 数导致调度开销过高。
* 当检测到 cgroup CPU quota 小于 1 核时，脚本会按 CPU 严重受限容器处理：限制 `GOMAXPROCS=1`，提高 `GOGC`，减少调度和 GC 额外开销。
* 后续可通过菜单 `44` 随时切换运行时性能档位；其中省资源稳连和高吞吐/跑满带宽模式会关闭自动流量统计并移除 iptables 统计规则，减少包路径开销。
* 菜单 `55` 可尝试应用网络栈优化；容器无权限的 sysctl 项会被跳过，首次修改前会记录原值，完整卸载时恢复。
* 未检测到明确内存限制时，Alpine 使用更保守推荐值，Debian / Ubuntu 使用略高推荐值；检测到 128/256/512MiB 等小内存容器时会自动下调 `GOMEMLIMIT`，同时避免把 `GOGC` 压得过低导致 CPU 消耗过高。

也可以通过环境变量直接指定并重写服务：

```sh
MIHOMO_GOMEMLIMIT=384MiB MIHOMO_GOGC=150 MIHOMO_GOMAXPROCS=2 MIHOMO_GODEBUG=madvdontneed=1 mh install
```

如果容器内存极低、CPU quota 小于 1 核，或多线程测速后仍然断流，优先在菜单 `44` 使用 `省资源稳连模式`；需要压测带宽时使用 `高吞吐/跑满带宽模式`，该模式同样会暂停自动流量统计和 iptables 统计链。

节点链接里的公网 IP 会缓存到 `/etc/mihomo/public.ip`，默认 6 小时自动过期。也可以删除该文件立即刷新，或通过环境变量 `MIHOMO_PUBLIC_IP_CACHE_TTL` 调整缓存秒数。

### 🌐 IPv6 使用说明

默认保持 IPv4 兼容模式。需要 IPv6 时，在菜单输入 `66` 开启：

* 选择 `2`：Mihomo 监听 IPv6，节点分享链接仍优先使用 IPv4。
* 选择 `3`：Mihomo 监听 IPv6，节点分享链接优先使用 IPv6，链接中的 IPv6 地址会自动添加方括号。
* 选择 `4`：手动写入分享 IP，适合 VPS 有多个 IPv6 或自动识别不准确的情况。

开启 IPv6 后请确认 VPS、LXC 宿主机、防火墙和云厂商安全组均已放行对应端口的 IPv6 入站流量。

### 👥 多用户管理说明

多用户管理只能在首次执行 `mh install` 安装 Mihomo 内核时选择是否启用。未启用时，主菜单不会显示 `77`，也不会创建 `/etc/mihomo/users.db`。

启用后，用户会绑定到已有节点。添加用户时可手动指定独立监听端口，也可直接回车自动分配；脚本会根据原节点参数渲染独立 listener：

* VLESS + Reality / VLESS + WebSocket：为用户生成独立 UUID。
* Hysteria2 / AnyTLS：为用户生成独立密码。
* 到期、禁用和超出流量配额的用户会在重新渲染配置时自动从独立 listener 中排除。
* 菜单 `77` -> `8` 会通过 iptables 按用户端口刷新流量统计，也可执行 `mh traffic`；开启 IPv6 监听时会同步使用 `ip6tables` 统计 IPv6 流量。
* 第一次刷新会建立 `/etc/mihomo/traffic.db` 快照；后续刷新会按用户端口的实际协议统计入站和出站字节增量，Hysteria2 只挂 UDP 规则，VLESS / AnyTLS 只挂 TCP 规则，减少低配容器的包路径 CPU 开销。
* 手动刷新流量统计只在用户达到流量配额、需要移除 listener 时才会重载服务。
* 用户端口、启停状态、到期/配额或用户列表变化时，脚本会重建 iptables 统计规则并重置流量快照，已累计的 `used_bytes` 不会被清零。
* 该方案不再依赖 Mihomo `/connections` 是否返回用户字段。LXC 容器需要具备 iptables / ip6tables / NET_ADMIN 权限，否则只能管理用户，无法读取端口流量计数。
* 菜单 `77` -> `9` 可重置指定用户的已用流量，便于测试配额。
* 菜单 `77` -> `10` 可输出指定用户的单节点链接和 Base64 订阅，也可执行 `mh sub-user`。
* 菜单 `77` -> `11` 可修改指定用户的独立监听端口。
* 菜单 `77` -> `12` 可启用或关闭每 10 分钟自动刷新流量统计，也可执行 `mh traffic-cron`；自动任务通过 root crontab 调用 `mh traffic-auto`，并使用轻量锁避免刷新重叠。
* 自动刷新只记录用量，不会在后台主动重启 Mihomo；需要立即执行超额用户限制时，手动运行 `mh traffic` 或在面板执行 `77` -> `7`。
* 如果低配 Alpine/LXC 需要优先降低 CPU 或跑满带宽，可在菜单 `44` 使用省资源稳连或高吞吐/跑满带宽模式。两者都会关闭自动流量统计并清理 iptables 统计规则；之后手动执行 `mh traffic` 会重新建立统计规则。
