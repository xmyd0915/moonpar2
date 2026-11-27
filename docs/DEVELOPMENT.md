# 开发与发布

开发与发布使用 MoonBit/core `1.0.0-rc1+3c0520448`，CLI 依赖 Node.js 24。`python tests/toolchain.py` 记录实际编译器并检查固定版本。Python 3 用于运行独立验证。运行步骤见 README。

- `packet.mbt` 负责校验和重同步；`volume.mbt` 组装元数据。
- `split.mbt` 保留包内容并分组恢复卷；`cmd/main/volumes.mbt` 负责同组发现及排他写出；`tests/volumes.py` 覆盖跨工具分卷工作流。
- `manifest.mbt` 处理文件描述、路径与块视图；`create.mbt` 写卷。
- `field.mbt`、`encode.mbt`、`recover.mbt` 处理有限域及恢复方程。
- `verify.mbt` 与 `repair.mbt` 提供文件级接口；Node I/O 集中在 `cmd/main`。
- `stream.mbt` 提供分块 I/O 回调；`checksum.mbt` 提供增量 MD5；`cmd/main/stream_io.mbt` 负责磁盘分块与暂存交付。
- 新增格式功能必须给出规范位置、正例、错误输入以及独立参考验证；无法互操作的功能在矩阵中单列。

提交前运行格式检查、全目标静态检查、JS/Wasm GC 测试、演示及互操作入口。公有接口变更后运行 `moon info --target js`，提交生成的 `.mbti`。

发布前更新 `moon.mod`、CLI 版本与 Creator 标识，执行 `moon package --list` 并检查 ZIP 内容。GitHub CI 通过后发布 Mooncakes；再在仓库之外创建全新模块，使用 `moon add` 安装指定版本，验证真实调用，且不配置本地依赖覆盖。

编译产物和测试临时文件位于 `_build/`。更新容量说明时，记录实测输入大小、峰值内存和恢复输出的完整摘要。
