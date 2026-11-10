# 分卷恢复

分卷适合把恢复数据分开存放或传输。文件集和恢复运算不变：索引保存清单与校验，恢复分卷保存指定数量的恢复块，各自携带两份元数据。丢失索引后仍可从剩余分卷加载文件信息。

## 创建与恢复

```sh
node moonpar2.cjs create --slice-size 4096 --recovery-blocks 8 --volume-blocks 2 archive.par2 documents
node moonpar2.cjs inspect archive.par2
node moonpar2.cjs verify archive.par2
node moonpar2.cjs repair restored archive.vol002+002.par2
```

输出包括 `archive.par2` 和 4 个恢复分卷。名称中的两个数字分别是首个恢复块的指数和该卷的恢复块数，最后一卷可少于指定数目。`--volume-blocks` 为 1–32，`--recovery-blocks` 仍指定总恢复块数。默认省略 `--volume-blocks` 时保持单卷行为。

如果删除索引和一个含 2 块的恢复分卷，剩下 6 个恢复块；读取任意剩余分卷即可加载同组数据。最多可修复多少损失取决于有效恢复方程的独立性。坏包会被跳过；一个分卷的部分包损坏不会自动使其他包失效。

## 发现与精确选择

发现范围限于每个显式输入所在目录，名称匹配同 stem 的 `.par2` 索引和 `.vol数字+数字.par2` 分卷。扩展名和 `vol` 标记兼容大小写；stem 按所在平台文件名大小写规则匹配。相近前缀、备份后缀和其他集合名称不会被自动加入。绝对路径与相对路径的同一输入会去重。

```sh
node moonpar2.cjs repair --no-discovery restored archive.vol002+002.par2 archive.vol006+002.par2
```

此时只使用列出的卷，适合检验单卷可用性或只采用选定副本。显式路径保留在前，默认源数据根目录仍是第一个显式卷的目录；可使用 `--base-dir` 指定。若同名分卷实际来自不同恢复集合，将报告集合冲突。

## 写出与应用接入

全部目标名称必须不存在。命令行先暂存全部卷，再逐个排他发布；正常捕获的写入错误会回滚本次已创建的文件并清理暂存，已有文件保持原样。进程被强制终止或断电不属于可捕获错误，可能留下部分卷；重新执行前应检查输出。

库调用 `split_volume(volume, recovery_blocks_per_volume=2)`，返回索引在前的字节数组。输入必须是完整且有效的单集合卷，恢复指数和各包内容保持不变，重复包去重。API 不命名文件、不操作磁盘，可用于将生成的恢复卷接入自己的存储服务。输出总体预算包含重复元数据，见[符合性矩阵](CONFORMANCE.md)。

`python tests/volumes.py --par2 /path/to/par2 --report _build/volumes.json` 验证两种工具分别写入和恢复、Unicode 目录、索引缺失、坏卷、输入选择、已有输出保护及写出失败回滚。与 par2cmdline 交换文件时，可直接传索引启动其自动发现。
