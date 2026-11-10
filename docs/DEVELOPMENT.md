# 开发与发布

工具链固定为 MoonBit/core `0.10.16+b1a0e846e`，CLI 依赖 Node.js 24。Python 3 用于独立验收。运行步骤见 README。

- `packet.mbt` 负责校验和重同步；`volume.mbt` 组装元数据。
- `manifest.mbt` 处理文件描述、路径与块视图；`create.mbt` 写卷。
- `field.mbt`、`encode.mbt`、`recover.mbt` 处理有限域及恢复方程。
- `verify.mbt` 与 `repair.mbt` 提供文件级接口；Node I/O 集中在 `cmd/main`。
- 新增格式功能必须给出规范位置、正例、错误输入以及独立参考验证；无法互操作的功能在矩阵中单列。

提交前运行格式检查、全目标静态检查、JS/Wasm GC 测试、演示及互操作入口。公有接口变更后运行 `moon info --target js`，提交生成的 `.mbti`。

发布前更新 `moon.mod`、CLI 版本与 Creator 标识，执行 `moon package --list` 并检查 ZIP 内容。GitHub CI 通过后发布 Mooncakes；再在仓库之外创建全新模块，使用 `moon add` 安装指定版本，验证真实调用，且不配置本地依赖覆盖。

不要提交编译产物、测试临时目录、账号凭据或个人报名资料。任何新的容量声明都需要精确边界、边界加一拒绝和修复内容比对。
