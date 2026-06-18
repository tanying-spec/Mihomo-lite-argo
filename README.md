# mihomo 一键配置脚本

一个面向 VPS 的 mihomo 管理脚本，支持 Ubuntu 22+、Debian 12+ 和 Alpine。安装后可以在命令行输入 `mh` 打开管理面板，通过数字菜单安装内核、生成节点、删除节点、重启服务、查看日志和卸载。

> 请在遵守当地法律法规、服务商条款和网络使用政策的前提下使用。

## 功能

- `1` 一键安装 mihomo 内核到 `/usr/local/bin/mihomo`
- `2` 一键生成 Shadowsocks 入站节点，并输出 mihomo 客户端节点片段
- `3` 删除已生成的节点
- `4` 重启 mihomo 服务
- `5` 查看实时日志
- `6` 卸载 mihomo、配置和 `mh` 命令
- `0` 退出脚本

## 快速安装

项目推送到 GitHub 后，把下面命令中的 `<用户名>` 和 `<仓库>` 替换为你的仓库信息：

```sh
curl -fsSL https://raw.githubusercontent.com/oKafuChino/Mihomo-lite/main/install.sh | sudo sh
```

## 目录和服务

- 管理命令：`/usr/local/bin/mh`
- mihomo 内核：`/usr/local/bin/mihomo`
- 配置目录：`/etc/mihomo`
- 主配置：`/etc/mihomo/config.yaml`
- 节点记录：`/etc/mihomo/nodes.db`
- 日志目录：`/var/log/mihomo`
- 服务名：`mihomo`

脚本会在 Debian/Ubuntu 上创建 systemd 服务，在 Alpine 上创建 OpenRC 服务。

## 参考

- [mihomo GitHub 仓库](https://github.com/MetaCubeX/mihomo)
- [mihomo listeners 配置文档](https://wiki.metacubex.one/config/inbound/listeners/ss/)
