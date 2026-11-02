# MoonPar2

MoonPar2 给一组小文件创建 PAR2 恢复卷。备份中的文件丢失或部分损坏后，可以用恢复卷定位坏块，把完整文件写到一个新目录。也可以读取 par2cmdline 生成的索引和分卷。

## 构建和演示

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/) 和 Node.js 24。下面的命令在仓库根目录运行。最后一步需要 Python 3，只用于演示。

```sh
moon build cmd/main --target js
node _build/js/debug/build/cmd/main/main.js --help
python examples/repair_demo.py
```

演示在临时目录中生成两个小文件和恢复卷，删除 `notes.txt`，改坏 `scan.bin` 的最后一个字节，再将两份文件还原到新目录。成功时会看到两行 `SHA-256 matches`。

## 保护和修复自己的文件

把编译好的 `_build/js/debug/build/cmd/main/main.js` 复制到工具目录，命名为 `moonpar2.cjs`。在待备份的文件夹中运行以下命令，将示例中的脚本路径替换为实际位置。

```sh
node /path/to/moonpar2.cjs create photos.par2 scan.bin notes.txt
node /path/to/moonpar2.cjs verify photos.par2
node /path/to/moonpar2.cjs repair restored photos.par2
```

- **创建**会在当前目录生成一个卷，包含文件清单、分块校验值和四个恢复块。卷名必须尚未被使用。请妥善保存恢复卷。
- **校验**从第一个卷所在目录读取源文件，逐个报告正常、缺失或损坏。退出码 0 表示全部正常，1 表示发现损坏或缺失，2 表示参数、输入格式或文件操作错误。
- **修复**先在内存中重建并验证所有文件，再写入指定的新目录。原始文件不会被覆盖。若磁盘写入中断，使用另一个新目录重试。
- 对于官方工具生成的多个卷，显式传入需要的分卷，例如 `repair restored set.par2 set.vol0+1.par2 set.vol1+2.par2`。只有索引时仍可校验，但修复需要足够的独立恢复块。

## 支持范围

适合文档、配置、样本等小型备份集。当前按固定偏移检查数据，不扫描重命名的文件或发生字节插入、删除后移位的文件。校验会识别损坏；修复能力取决于丢失的块数及可用恢复块。

| 项目 | 范围 |
| --- | --- |
| 源文件 | 最多 64 个非空普通文件，总计 4 MiB；单层目录，使用可移植的 ASCII 文件名 |
| 分块 | 命令行创建时为 4096 字节。读取时支持 4 字节的倍数，最大 64 KiB，最多 1024 个源块 |
| 恢复数据 | 读取最多 32 个不同的恢复块，所有输入卷合计最多 16 MiB |
| 运行环境 | 核心库使用 MoonBit；命令行使用 Node.js 读写本地文件，无运行时网络服务 |

## 正确性验证

```sh
moon check --target js --deny-warn
moon test --target js --deny-warn
moon build cmd/main --target js --deny-warn
python tests/interop.py --par2 /path/to/par2
```

交叉测试使用 [par2cmdline 1.4.0](https://github.com/Parchive/par2cmdline/releases/tag/v1.4.0)。两种工具分别创建恢复卷；随后同时改坏一个文件、删除另一个，分别用两个工具修复并比对原件 SHA-256。测试还覆盖恢复数据不足和输出路径已存在的情况。

格式依据 [Parity Volume Set Specification 2.0](https://parchive.sourceforge.net/docs/specifications/parity-volume-spec/article-spec.html)。命令行调用自己的 MoonBit 编解码实现；par2cmdline 仅用于交叉验证。许可证为 [MIT](LICENSE)。
