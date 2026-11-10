# MoonPar2

用 MoonBit 创建、校验和修复 PAR2 恢复卷。保护多级目录中的文档、照片和归档；文件误删或局部损坏后，将原始内容重建到新目录。恢复卷自身有局部损坏时，工具会报告并跳过坏包，继续使用其余有效数据。

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

- `create` 接受文件或目录，递归收集普通文件。默认生成 4 个恢复块，可选 1–32 个；`--slice-size` 指定块宽，省略则自动选择。目标卷必须不存在。
- `inspect` 列出创建工具、文件角色、可用恢复块和坏包诊断，无需读取源文件。
- `verify` 检查源文件。退出码 0 为全部正常，1 为文件缺失或损坏，2 为参数、格式或文件操作错误。坏包告警与源文件状态分别报告。
- `repair` 在整文件校验通过后写入新的输出目录，自动建立子目录，保留原件。恢复块不足时返回 2，不创建输出目录；写盘中断后请使用另一个新目录重试。
- `--base-dir ROOT` 显式指定数据根目录。读取默认以第一个卷所在目录为根；多个卷需要显式列出。
- `create --check-only FILE` 将文件记入仅校验列表；修复输出只包含参与恢复的文件。这一选项有[第三方兼容限制](docs/CONFORMANCE.md)，与 par2cmdline 交换卷时建议使用默认模式。

## 作为 MoonBit 库

```sh
moon add xmyd0915/moonpar2@0.2.0
```

在包配置导入 `"xmyd0915/moonpar2" @par`，通过 `create`、`read_set`、`verify`、`repair` 处理内存数据。核心库不访问磁盘、不调用外部 PAR2 程序。完整[调用示例](examples/library/main.mbt)可以通过 `moon run examples/library --target js` 运行。

## 支持范围

| 项目 | 0.2.0 |
| --- | --- |
| 文件与目录 | 最多 4096 个普通文件，含空文件；多级相对路径，可移植 ASCII 名称 |
| 容量 | 总计 256 MiB，整组在内存中处理 |
| 源块 | 最多 32768 个，块宽为 4 的倍数、至多 256 KiB |
| 恢复数据 | 最多 32 个不同恢复块，输入卷总计 64 MiB |
| 容错 | 坏包跳过、错位重同步、重复元数据、多卷合并、未知包忽略 |
| 路径保护 | 拒绝越界、绝对路径、设备名、冲突布局、符号链接与目录联接 |

修复能力取决于损失块数和剩余恢复方程的独立性，不等于一定能恢复整个丢失文件。256 MiB 集合默认块宽为 256 KiB；8 个恢复块约占 2 MiB 加元数据，可修复至多 8 个丢失块。空目录、Unicode 扩展、源数据错位扫描和大文件流式处理未实现。

本机 Windows / Node.js 24 对 256 MiB 测试集的一次测量：创建 11.44 秒，修复 16.28 秒，修复峰值内存约 597 MiB。速度随硬件、源块和恢复块数量变化。

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
```

参考工具固定为 [par2cmdline 1.4.0](https://github.com/Parchive/par2cmdline/releases/tag/v1.4.0)。双方分别写入、读取和修复目录备份，修复结果以 SHA-256 比对；四类核心数据包还做逐字节对照。仅校验列表的已知互操作限制独立报告，不计入通过项。

许可证：[MIT](LICENSE)。维护说明和版本变化见[开发指南](docs/DEVELOPMENT.md)及[变更记录](CHANGELOG.md)。
