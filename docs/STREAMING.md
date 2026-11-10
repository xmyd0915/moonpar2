# 接入分块存储

`create_stream`、`verify_stream`、`repair_stream` 将 PAR2 运算与文件系统分开。调用方可以接入本地磁盘或支持按偏移读取的对象存储。CLI 的适配见 `cmd/main/stream_io.mbt`；不依赖磁盘的可运行示例见 [examples/streaming](../examples/streaming/main.mbt)：

```sh
moon run examples/streaming --target js
```

## 回调契约

| 回调 | 约定 |
| --- | --- |
| `reader(name, offset, length)` | 返回指定位置的恰好 `length` 字节；`offset` 是 UInt64；短读或存储错误应抛出异常 |
| `size(name)` | 返回当前 UInt64 文件长度；不存在返回 `None`，权限或 I/O 错误抛出异常 |
| `writer(name, offset, bytes)` | 将该块写入暂存对象；异常向外传播。空文件也会收到一次偏移为零的空写入 |

`FileInfo` 提供名称、UInt64 长度和 `recoverable` 角色。仅校验成员参与整文件 MD5 校验，不参与恢复矩阵，也不会交给修复写入回调。`files()` 可用于读取集合的名称、长度和角色。

创建会先读取源数据生成文件校验与块校验，再次读取参与恢复的数据计算恢复块；两次之间改变的源块会使创建失败。校验按块读取并返回各文件状态。修复先定位坏块，再消去完好数据并求解缺失块，最后分块写入全部恢复成员。

修复可能在部分暂存写入后发现整文件校验失败或 I/O 错误。只有 `repair_stream` 成功返回，调用方才能将暂存对象交付给用户；失败时清理暂存内容。CLI 实现了这一流程及写盘中断清理。同步回调可以通过抛出异常中止操作。

## 内存与尺寸

读取粒度最多为集合块宽，源文件本身不整体留在内存。恢复卷和块校验元数据仍在内存中；运算工作区随恢复块数量、块宽变化。磁盘适配必须保留 UInt64 偏移语义，不能转换为 32 位整数。Node 的精确整数范围覆盖本库的 512 GiB 地址预算。

默认块宽按总长度选择；显式设置块宽时，应同时考虑源块数量和冗余量。[符合性矩阵](CONFORMANCE.md)列出资源预算；[大文件验收脚本](../tests/streaming.py)使用真实数据、256 MiB Node 堆限制和完整 SHA-256 验证恢复结果。
