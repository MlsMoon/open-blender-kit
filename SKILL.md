---
name: open-blender-kit
description: 通过 MoonArtsToolCLI 操作隔离 Blender 实例，完成建模、场景检查、渲染、保存与 FBX/GLB 导出。
license: MIT
metadata:
  author: MlsMoon
---

# Blender：命令行建模工具

唯一工具入口为 MoonArtsToolCLI。此仓库保留 open-blender-kit 身份，可在不同宿主项目使用。
先读取真实场景；进程存在、命令已入队或作业仍在运行都不等于成功。

## 入口与检查

从宿主项目根执行下例；安装位置不同则使用实际 Skill 路径。
包装脚本从当前目录和 Skill 所在目录向上发现 Tools/MoonArtsTool。
也可由调用进程设置 MOON_ARTS_TOOL_DIR 指向含 EXE 和 manifest.json 的目录，不落盘机器路径。

```powershell
pwsh .agents/skills/open-blender-kit/scripts/moon.ps1 blender status
pwsh .agents/skills/open-blender-kit/scripts/moon.ps1 blender capabilities
pwsh .agents/skills/open-blender-kit/scripts/moon.ps1 blender start --blender <运行时发现的软件路径>
pwsh .agents/skills/open-blender-kit/scripts/moon.ps1 blender scene --instance <返回的实例>
pwsh .agents/skills/open-blender-kit/scripts/moon.ps1 blender execute --instance <实例> --script <可信脚本.py> --wait 10
pwsh .agents/skills/open-blender-kit/scripts/moon.ps1 blender job --instance <实例> --id <作业> --wait 10
```

优先复用 Launcher 配置中的 Blender 路径；缺软件或内置工具时报告缺口，不自动安装或发布。
包装脚本核对 manifest 的文件名、协议与 SHA256；校验用于发现错配，不等同于发布签名。

## 操作与持久化

- 默认创建本任务独立的 GUI 事件循环实例并隐藏窗口；用户要看编辑器时使用 --visible。
- 所有修改明确指定实例；按几何、材质、灯光、渲染与导出分段执行并回读 scene/inspect。
- 先查本地 capabilities，再查指定实例的 capabilities；旧 worker 不自动热更新。
- 保存用 save --instance <实例> --output <新文件.blend>；导出用 export 并指定 collection 与 output。
- render 使用当前相机输出 PNG；frame 会改变相机并标脏，不把取景当只读检查。
- 覆盖须显式 --overwrite；关闭脏实例默认拒绝，丢弃未保存内容须有明确授权。
- 导出要求 Object Mode、集合对象可选并处于当前 view layer；FBX 单位、轴向和节点缩放一起核对。
- 写入可用 --request-id；同 ID 同内容复用作业，冲突内容拒绝。超时继续查询原 job，不重发写入。
- 仅 succeeded 表示作业完成；failed/interrupted 先检查错误、实际状态和已保存产物。
- 不保存、关闭或覆盖用户其他实例；不因超时终止编辑器。保存后仍需确认 clean 状态。

## 按需参考

- 工具发现、内置副本维护与故障定位：[工具维护](references/moon-tool.md)。
- 固定视角厚玻璃、Cycles 设备、透明 Alpha 与单层代理：[玻璃烘焙](references/cycles-fixed-view-glass-bake.md)。
- 隔离示例脚本 scripts/build_suzanne.py 提供 build_suzanne(output_dir)；只在全新任务实例运行，会清空该实例场景。输出目录必须是新目录。
- 导出网格检查可使用 3d-model-data-reader；宿主资产绑定与序列化规则由宿主持有。

## 验收

CLI 回执、实际场景、渲染图片、导出数据与宿主效果分别记录。
渲染应查看图片，模型应回读几何/UV/层级/单位；不把 status 或文件存在当视觉通过。
