# open-blender-kit

使用 MoonArtsToolCLI 驱动隔离 Blender 实例的 Agent Skill。
支持建模、场景检查、渲染、保存和 FBX/GLB 导出；身份与 Git 仓库保持 open-blender-kit。

## 安装与前提

将本仓库放入宿主的技能目录，读取 [SKILL.md](SKILL.md)。
需要 PowerShell 7、已安装的 Blender，以及宿主提供的 MoonArtsToolCLI.exe / manifest.json 配对文件。
本仓库不分发 CLI 二进制，也不自动下载或安装软件。

包装脚本从当前目录及 Skill 所在目录向上发现 Tools/MoonArtsTool。
独立安装时由调用进程设置 MOON_ARTS_TOOL_DIR 指向工具目录。

```powershell
pwsh ./scripts/moon.ps1 blender status
pwsh ./scripts/moon.ps1 blender capabilities
```

命令示例从本 Skill 根执行；参数以实际 CLI --help 和 capabilities 为准。
工具维护见 [工具维护](references/moon-tool.md)，效果专题见 [玻璃烘焙](references/cycles-fixed-view-glass-bake.md)。

## 仓库

[源代码](https://github.com/MlsMoon/open-blender-kit)。
此目录本身是独立 Git 仓库。提交与推送在此仓库按授权范围进行，宿主版本管理另行处理。
目录名与 SKILL.md 的 name 保持一致；本机路径不写入版本控制。

## License

[MIT](LICENSE) © MlsMoon
