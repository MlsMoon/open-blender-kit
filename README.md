# open-blender-kit

An [Agent Skill](https://agentskills.io/specification) that teaches AI agents how to configure, repair, and use the local **Blender MCP** on Windows: modeling, scene checks, screenshots, save, and GLB / FBX export.

This repository **is** the skill folder. The directory name, GitHub repo name, and `SKILL.md` `name` field must all stay `open-blender-kit`.

It is not tied to any game project.

## Source repository

This folder is its own Git repository. A Plastic SCM pull of a game project usually copies the files and **drops `.git`**.

- Git: https://github.com/MlsMoon/open-blender-kit
- Install / update: [Moon Game Dev Tool Manager](https://github.com/MlsMoon/moon-game-dev-tool-manager)

Commit and push skill changes in that Git repo. Do not treat a copy inside one Unity workspace as the place to publish.

## What you get

| Need | Where |
|---|---|
| Install / repair MCP, launch, Suzanne smoke | `scripts/ensure.ps1` |
| Modeling rules and fault table | `SKILL.md` |
| Fixed-view Cycles glass bake | `references/cycles-fixed-view-glass-bake.md` |
| Machine-local Blender path and port | `local/blender.local.json` (copy the `.example`) |

## Install

Clone into your agent's skills directory. Keep the folder name:

```bash
# Claude Code
git clone https://github.com/MlsMoon/open-blender-kit.git \
  ~/.claude/skills/open-blender-kit

# Codex / other agents
git clone https://github.com/MlsMoon/open-blender-kit.git \
  ~/.agents/skills/open-blender-kit
```

Or install with [Moon Game Dev Tool Manager](https://github.com/MlsMoon/moon-game-dev-tool-manager) (catalog id `open-blender-kit`).

Then:

```powershell
copy local\blender.local.json.example local\blender.local.json
pwsh scripts/ensure.ps1
```

## License

[MIT](LICENSE) © MlsMoon
