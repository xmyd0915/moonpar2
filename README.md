# MoonPar2

用 MoonBit 创建、校验和修复 PAR2 恢复卷。支持中文目录和大文件流式处理，保护文档、照片和归档；文件误删或局部损坏后，将原始内容重建到新目录。恢复卷自身有局部损坏时，工具会报告并跳过坏包，继续使用其余有效数据。

## 先运行一次完整演示

安装 [MoonBit](https://www.moonbitlang.com/download/)、Node.js 24 和 Python 3。在仓库根目录执行：

```sh
moon build cmd/main --target js
python examples/repair_demo.py
```

演示创建一个多级目录备份，然后删除文本和空文件、改坏照片数据，并损坏恢复卷中的一个包。工具修复三份文件，脚本逐一验证 SHA-256。输入、预期输出和自己的目录用法见[演示指南](docs/WALKTHROUGH.md)。

## 日常使用

构建后将 `_build/js/debug/build/cmd/main/main.js` 复制为 `moonpar2.cjs`。在数据根目录执行：

```sh
node /path/to/moonpar2.cjs create --recovery-blocks 8 backup.par2 documents photos
node /path/to/moonpar2.cjs inspect backup.par2
node /path/to/moonpar2.cjs verify backup.par2
node /path/to/moonpar2.cjs repair restored backup.par2
```

- `create` 接受文件或目录，递归收集普通文件。默认生成 4 个恢复块，可选 1–32 个；`--slice-size` 指定块宽，省略则自动选择。`--volume-blocks N` 每 N 个恢复块写一个分卷，另生成索引；省略则保持单卷输出。目标文件必须不存在。
- `inspect` 列出创建工具、文件角色、可用恢复块和坏包诊断，无需读取源文件。
- `verify` 检查源文件。退出码 0 为全部正常，1 为文件缺失或损坏，2 为参数、格式或文件操作错误。坏包告警与源文件状态分别报告。
- `repair` 分块读取和写入暂存目录，整文件校验通过后交付到新的输出目录，自动建立子目录，保留原件。恢复块不足时返回 2，不创建输出目录；交付时写盘中断后请使用另一个新目录重试。
- `--base-dir ROOT` 显式指定数据根目录。读取默认以第一个卷所在目录为根；从索引或任意恢复分卷自动发现同目录的同名分卷组。`--no-discovery` 仅使用显式列出的卷，适合精确选择剩余恢复数据。
- `create --check-only FILE` 将文件记入仅校验列表；修复输出只包含参与恢复的文件。已通过 MultiPar 校验和修复验证；par2cmdline 1.4.0 对这一标准功能有[已定位的实现缺陷](docs/CONFORMANCE.md)。

## 作为 MoonBit 库

```sh
moon add xmyd0915/moonpar2@0.4.0
```

在包配置导入 `"xmyd0915/moonpar2" @par`，通过 `create`、`read_set`、`verify`、`repair` 处理内存数据。大文件应用使用 `create_stream`、`verify_stream`、`repair_stream`，通过回调提供分块读写；长度及偏移采用 UInt64。核心库不访问磁盘、不调用外部 PAR2 程序。完整[调用示例](examples/library/main.mbt)可以通过 `moon run examples/library --target js` 运行。

接入磁盘或对象存储时，参阅[流式接口指南](docs/STREAMING.md)及可运行的 [Unicode 恢复示例](examples/streaming/main.mbt)。

## 支持范围

| 项目 | 0.4.0 |
| --- | --- |
| 文件与目录 | 最多 4096 个普通文件，含空文件；中文、日文、emoji 和多级相对路径 |
| 大文件 | 命令行默认流式处理；64 位长度与偏移，内存不随源文件总量线性增长 |
| 源块 | 最多 32768 个，块宽为 4 的倍数，自动选择或手动指定 |
| 恢复数据 | 最多 32 个不同恢复块，输入卷总计 64 MiB |
| 容错 | 坏包跳过、错位重同步、重复元数据、多卷合并、未知包忽略 |
| 分卷 | 索引与恢复分卷写出、同组自动发现、各恢复分卷自带两份元数据 |
| 路径保护 | 拒绝越界、绝对路径、设备名、冲突布局、符号链接与目录联接 |

修复能力取决于损失块数和剩余恢复方程的独立性，不等于一定能恢复整个丢失文件。恢复块数量和块宽共同决定冗余量；例如 8 个 256 KiB 恢复块约占 2 MiB 加元数据，可修复至多 8 个丢失块。空目录、源数据错位扫描及 Packed 扩展未实现。

大文件验收可运行 `python tests/streaming.py --mib 4096 --par2 /path/to/par2`：脚本使用超过 4 GiB 的真实文件，在 256 MiB Node 堆限制下创建、校验和修复，检查完整 SHA-256 和进程峰值内存。

## 分开存放恢复数据

```sh
node moonpar2.cjs create --recovery-blocks 8 --volume-blocks 2 backup.par2 documents photos
node moonpar2.cjs repair restored backup.par2
```

这会生成 `backup.par2` 索引及 `backup.vol000+002.par2`、`backup.vol002+002.par2`、`backup.vol004+002.par2`、`backup.vol006+002.par2`。每个分卷有 2 个恢复块；索引不含恢复块。将需要使用的剩余分卷放回同一目录，再从索引或任意分卷启动修复。索引丢失不妨碍读取分卷，实际修复能力由剩余有效块决定。命名、发现规则和故障案例见[分卷指南](docs/VOLUMES.md)。

## 验证与维护

[PAR2 2.0 覆盖矩阵](docs/CONFORMANCE.md)逐项说明核心包、路径、资源预算和未实现扩展。[GitHub Actions](https://github.com/xmyd0915/moonpar2/actions)在 Ubuntu 和 Windows 运行同一组测试，并保存覆盖结果。

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build cmd/main --target js --deny-warn
python tests/conformance.py --par2 /path/to/par2 --report _build/conformance.json
python tests/capacity.py --mib 256 --par2 /path/to/par2 --report _build/capacity.json
python tests/streaming.py --mib 1024 --par2 /path/to/par2 --report _build/streaming.json
python tests/unicode_interop.py --par2 /path/to/par2
python tests/volumes.py --par2 /path/to/par2 --report _build/volumes.json
```

参考工具固定为 [par2cmdline 1.4.0](https://github.com/Parchive/par2cmdline/releases/tag/v1.4.0) 和 [MultiPar 1.3.3.6](https://github.com/Yutaka-Sawada/MultiPar/releases/tag/v1.3.3.6) 官方包。双方分别写入、读取和修复目录备份，修复结果以 SHA-256 比对；四类核心数据包还做逐字节对照。中文目录通过两款工具双向修复；MultiPar 还验证仅校验列表及相关恢复。Windows CI 下载固定 SHA-256 的 MultiPar 归档完成验证。

许可证：[MIT](LICENSE)。维护说明和版本变化见[开发指南](docs/DEVELOPMENT.md)及[变更记录](CHANGELOG.md)。
