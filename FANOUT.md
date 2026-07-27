# fanout 出口节点

安装并启动 fanout 后，Mihomo 可以为每个 fanout SOCKS5 出口生成一个独立的 VLESS 节点。新节点复用已有 VLESS Reality 或 VLESS-WS 的入口、域名、端口和传输参数，但使用独立 UUID；只有这个 UUID 的流量会经过 fanout，原节点继续使用服务器直接出口。

## 菜单

运行 `mh`，选择 `99`：

- 新建 fanout 专用节点；
- 查看节点状态和分享链接；
- 删除 fanout 专用节点。

脚本默认选择第一个已有 VLESS 节点，以及 `/var/lib/fanout/state.json` 中第一条隧道的 SOCKS5 端口。

## 命令

```sh
mh fanout list
mh fanout add JP-Fanout
mh fanout add JP-Fanout vless-ws 42510
MIHOMO_FANOUT_DELETE_CONFIRM=DELETE mh fanout delete JP-Fanout
```

映射保存在 `/etc/mihomo/fanout-bindings.db`，配置重建和脚本更新不会丢失。新增前会验证 SOCKS5 正在 `127.0.0.1` 监听并能真实访问公网；Mihomo 配置检查或重启失败时会自动恢复数据库和原配置。

fanout 隧道掉线时，专用节点会暂时无法出网，但原节点不受影响。fanout 在相同槽位重连后会保持 SOCKS5 端口不变，专用节点会自动恢复。
