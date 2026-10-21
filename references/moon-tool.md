# Moon Arts 工具维护

宿主提供 Tools/MoonArtsTool/MoonArtsToolCLI.exe 与 manifest.json。
包装脚本按当前目录和 Skill 位置向上寻找，或使用调用进程的 MOON_ARTS_TOOL_DIR。
SHA256 用于检查配对与损坏，不代表发布者身份认证。

## 查询与故障

- 首先运行 blender status / capabilities；连接实际实例后再次查询 capabilities --instance。
- 缺失文件：由宿主版本管理恢复配对副本，或在已授权的源码仓构建；不自动下载与发布。
- hash 不匹配：停止，不跳过校验；恢复同一版本 EXE 与 manifest。
- 作业超时：用 job --instance <实例> --id <作业> --wait 10 查询同一作业。
- worker 版本不匹配：保存现有任务后创建新隔离实例，不能强制更新用户的活动实例。
- 失败先查看错误和产物，再决定修复；不能把查询超时当成写操作失败而重复执行。

## 更新内置副本

CLI 源码与打包能力由宿主运行时发现，不把个人源码位置写入此仓库。
仅在用户授权更新工具时，在已核实的源码根执行对应构建与宿主打包入口。
EXE 与 manifest 成对更新，核对真实命令帮助和 capabilities，不把源码更新当二进制已更新。
不改变源码仓可见性或擅自发布 Release。

## 功能验收

使用最终 EXE 与全新隔离实例，检查：
- 启动命令结束后仍可 scene/inspect；
- execute、save、export、render 与实际产物；
- 重复 ID 不重复执行、冲突 ID 拒绝；
- 超时后继续查询同一作业、错误报告、覆盖和关闭保护。

图片需实际查看；导出需核对几何与单位；协议回包与宿主视觉效果分开验收。
本 Skill 仅管理 Blender 用法；宿主若复用包装脚本转发其他 CLI 子命令，其业务规范仍由宿主持有。
