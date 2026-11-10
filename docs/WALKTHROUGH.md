# 目录恢复演示

在仓库根目录执行：

```sh
moon build cmd/main --target js
python examples/repair_demo.py
```

需要 MoonBit 与 Node.js 24，演示脚本使用 Python 3。它只在临时目录操作，无需网络或 par2cmdline。

输入目录包含 `documents/notes.txt`、`documents/empty.txt`、`photos/2026/scan.bin`。脚本创建恢复卷后，删除前两个文件，翻转照片数据的最后一个字节，并破坏恢复卷中一个恢复块的包校验。

随后 `inspect` 显示剩余 3 个恢复块；`verify` 返回退出码 1，并指出两个缺失文件和一个损坏文件。`repair` 跳过坏包，把三份文件写入新目录。每份结果与操作前保留的 SHA-256 比对，均输出 `SHA-256 matches`。原件只用于测试断言，不会传给修复算法。

关键输出如下（SHA-256 在真实运行时完整显示）：

```text
warning: volume 1: skipped 4164 damaged or non-packet bytes
recovery blocks 3
missing documents/empty.txt (0 bad slices)
missing documents/notes.txt (1 bad slices)
damaged photos/2026/scan.bin (1 bad slices)
recovered 3 files into restored
```

## 用自己的目录

将构建产物 `_build/js/debug/build/cmd/main/main.js` 复制为 `moonpar2.cjs`。以下命令在数据根目录运行：

```sh
node /path/to/moonpar2.cjs create --recovery-blocks 8 backup.par2 documents photos
node /path/to/moonpar2.cjs inspect backup.par2
node /path/to/moonpar2.cjs verify backup.par2
node /path/to/moonpar2.cjs repair restored backup.par2
```

恢复卷与数据根目录不在同一位置时：

```sh
node /path/to/moonpar2.cjs repair --base-dir /path/to/data restored /path/to/volumes/set.par2 /path/to/volumes/set.vol0+4.par2
```

文件名必须符合[可移植路径规则](CONFORMANCE.md)。恢复卷损坏不会自动保证可修复：缺失全部关键元数据或缺少独立恢复块时，命令返回 2，不创建输出目录。

## 核对第三方互操作

```sh
python tests/conformance.py --par2 /path/to/par2 --report _build/conformance.json
```

此入口包含目录文件、同名不同路径、损坏校验、错误长度、插入字节、截断尾部、重复 Main、未知包、无足够恢复块、恶意路径、符号链接或目录联接、核心包字节一致性、32768 源块及 4096 文件边界。测试生成输入、执行两种工具并比对实际输出，不要求下载额外数据集。
