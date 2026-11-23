# Art source files

Working files for hand-made assets. Godot does not read this folder. Exports go to `game/assets/` under the naming rule in `docs/decisions/0004-asset-pipeline.md`.

| Folder | Tool | Typical export |
|---|---|---|
| `procreate/` | Procreate (`.procreate`) | `.png` to `game/assets/textures/` |
| `ableton/` | Ableton Live project folders | `.wav` to `game/assets/audio/samples/` or `game/assets/audio/ir/` |
| `blender/` | Blender (`.blend`) | `.glb` to `game/assets/meshes/` |
| `recordings/` | Field recordings, kept SuperCollider takes | `.wav` after editing |

Binary files here grow the repository with every revision. See the Git LFS note in decision 0004 before committing the first one.
