# PAR2 2.0 符合性与兼容范围

MoonPar2 的符合性目标是完整理解 [PAR2 2.0 核心格式](https://parchive.sourceforge.net/docs/specifications/parity-volume-spec/article-spec.html)的五类包、文件分组、块排序、校验与恢复关系，并在损坏卷中继续使用有效包。0.3.0 实现这些核心语义，并支持 Unicode Filename 和 64 位分块 I/O。下表列出已验证行为、资源范围及可选扩展。

## 核心覆盖矩阵

| 规范部分 | 0.3.0 行为 | 可运行证据 |
| --- | --- | --- |
| Packet Header | 识别魔数、小端长度、4 字节倍数及包 MD5；扫描按字节推进，不依赖损坏后仍然对齐 | `conformance_wbtest.mbt`；`tests/conformance.py` |
| 坏包与截断 | 丢弃校验失败的包；错误长度、插入字节和截断尾部不遮蔽后面的有效包；报告跳过字节数 | 两种写入器 × 两种修复器的 7 类卷样本 |
| 未知包、重复包、乱序 | 忽略未知类型；接受相同元数据及恢复块的重复副本；按 Main 中次序重组文件 | 独立构造的未知包和倒序包；重复元数据样本 |
| 冲突、不同集合 | 拒绝校验有效但内容冲突的重复关键元数据或恢复块；拒绝混合的已识别数据集合 | `volume.mbt` 与核心回归测试 |
| Main | 写入时按 128 位小端数值分别排序恢复及非恢复文件 ID；读取时保留两组角色和源块次序；只读校验集合允许零个恢复文件 | 与 par2cmdline 的核心包逐字节相等；空集合语义单测 |
| File Description | 整文件 MD5、前 16 KiB MD5、长度、名称和 ID；支持多级相对路径及空文件 | 嵌套同名文件、零字节文件、4096 文件恢复 |
| IFSC | 按源块顺序计算 CRC32 和 MD5，尾块补零；恢复文件缺失必要分块校验时拒绝加载 | 尾块损坏测试；标准包逐字节对照 |
| Recovery Slice | GF(2¹⁶)、生成多项式 0x1100B、标准源块常量和恢复指数；秩不足不产生结果 | 32768 个不同源块常量、32768 块实际文件、非零指数参考卷 |
| Creator | 写入版本和联系 URL；`inspect` 显示创建者；加载及修复失败附带已读取的创建者信息 | 演示输出及缺少 Main / 恢复块失败用例 |
| 单卷元数据冗余 | 写入两份 Main、FileDesc、IFSC；一份损坏可用另一份 | `bad-main-copy` 双向修复 |
| 多卷读取 | 合并显式传入的索引与分卷；恢复块去重，以实际剩余独立块决定能否修复 | par2cmdline 两个分卷及受损组合卷 |
| 仅校验文件 | 读取、生成、整文件校验；不参与恢复方程，不写进修复输出 | 核心单测、`--check-only` 集成测试；跨工具限制见下文 |

## 路径和文件系统策略

卷中路径相对数据根目录，分隔符为 `/`。创建可递归遍历目录；读取默认使用第一个卷所在目录，也可以通过 `--base-dir` 明确指定。恢复自动建立目标子目录，并要求输出根目录尚不存在。

支持 Unicode 名称（含中文、日文、emoji）、空格、括号、隐藏文件及每级至多 255 个 UTF-16 单元的路径组件；路径总长不超过 4096 个 UTF-16 单元，最多 64 级。拒绝绝对路径、盘符、父目录穿越、空路径组件、Windows 保留设备名、不兼容字符、尾部点或空格、完整路径大小写冲突以及同路径既是文件又是目录的冲突。

命令行对每一级已有路径组件检查符号链接和 Windows 目录联接，并拒绝跟随。输入打开时再次检查普通文件及读取长度，输出采用排他创建。测试覆盖输入、输出祖先联接和校验和完全有效的恶意路径包。跨平台路径检查不能替代操作系统沙箱：不要允许其他进程在运行期间恶意替换目录。

空目录、权限、时间戳与符号链接本身不是本版本的备份对象。源文件改名以及源数据插入、删除后的错位扫描尚未实现；卷内插入、删除字节后的包重同步则已实现。

## 资源范围

| 维度 | 上限与验证 |
| --- | --- |
| 文件数 | 4096 个；4096 个文件分布于 64 个目录的恢复通过，4097 个被拒绝 |
| 总输入 | 流式处理，64 位长度和偏移；内存接口保留 256 MiB 预算，大文件使用流式 API |
| 源块数 | 至多 32768；达到格式核心算法的源块数量上限。仅校验文件不占恢复方程的源块 |
| 块宽 | 4 的正整数倍，至多 16 MiB；创建可用 `--slice-size` 明确指定 |
| 恢复块 | 至多 32 个不同指数，指数范围 0–65535 |
| 输入卷 | 总计 64 MiB，命令行至多 256 个卷 |
| 扫描开销 | 每个卷的候选包哈希工作量限制为卷长的 4 倍；超限明确失败 |

创建、校验和修复通过回调逐块读写，使用 64 位长度及偏移。Node CLI 默认启用流式路径；修复先写暂存目录，全部文件校验通过后再交付。源文件总量地址预算为 512 GiB，仍受 32768 源块和块宽约束；这是地址能力，实测尺寸以验收报告为准。编码缓冲的有效恢复字节预算为 32 MiB，避免同时增大块宽和恢复块数导致无界分配。自动发现分卷和多卷写出尚未实现。

## 可选扩展

Unicode Filename（UTF-16LE）已实现读写及覆盖名称语义，同时支持 par2cmdline / MultiPar 通行的 UTF-8 FileDesc 名称。覆盖名称与回退名称均执行路径校验。ASCII/Unicode Comment、Input File Slice、Recovery File Slice Checksum、Packed Main、Packed Recovery Slice 尚未实现；有效未知包会被忽略，缺少核心 Main 的 Packed 集合明确失败。

## 独立参考验证

参考程序固定为 par2cmdline 1.4.0，下载归档有 SHA-256 校验。Main、FileDesc、IFSC、RecvSlic 在同样输入及参数下逐字节相等。目录和受损卷测试将两个工具分别作为写入器，再分别由两个工具修复；每个修复器只拿到测试中的受损卷，不会悄悄使用完好的旁路分卷。

par2cmdline 1.4.0 创建时会忽略空输入文件，因此它生成的目录样本不证明空文件重建能力。MoonPar2 自己创建的集合则有删除空文件后重建的独立测试。

显式非恢复文件列表已通过 MultiPar 的独立校验和恢复验证。par2cmdline 1.4.0 对同一功能在 Windows 异常退出、Linux 段错误：其代码仅为恢复文件分配 SourceBlocks，后续非恢复文件匹配路径却会访问该存储，见上游 [AllocateSourceBlocks 与匹配逻辑](https://github.com/Parchive/par2cmdline/blob/v1.4.0/src/par2repairer.cpp)。测试保留这一诊断，不将该工具的异常计为通过。与此版本交换卷时使用默认的全部文件参与恢复模式；需要非恢复集合时可使用 MultiPar。

## 运行覆盖检查

```sh
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build cmd/main --target js --deny-warn
python tests/conformance.py --par2 /path/to/par2 --report _build/conformance.json
python tests/capacity.py --mib 256 --par2 /path/to/par2 --report _build/capacity.json
python tests/streaming.py --mib 1024 --par2 /path/to/par2 --report _build/streaming.json
python tests/unicode_interop.py --par2 /path/to/par2 --multipar /path/to/par2j64.exe
```

GitHub Actions 在 Ubuntu 和 Windows 使用相同入口，并上传结果 JSON，便于逐项核对通过与兼容限制。
