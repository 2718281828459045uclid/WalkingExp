# 0004. Asset pipeline: sources outside the engine, exports inside, code reads data resources

Status: accepted, 2026-11-22.

## Context

`plan.md` calls for "a robust editing interface that separates code and assets and lets me swap out assets as I create them."

## Decision

Three layers, plus code:

| Layer | Location | Contents | Edited with |
|---|---|---|---|
| Source | `art-source/` | `.procreate`, Ableton project folders, `.blend`, raw recordings | Procreate, Ableton Live, Blender, SuperCollider |
| Export | `game/assets/` | `.png`, `.wav`, `.ogg`, `.glb`, fonts | Written by the source tool's export; not edited inside Godot |
| Data | `game/data/` | `.tres` Resources: parameter sets and references to exports | Godot Inspector |
| Code | `game/src/`, `game/shaders/` | `.gd`, `.gdshader` | Text editor |

Rule: code does not contain asset paths. A script declares an exported property of a Resource type; a scene assigns a Data resource to it. Example in the sandbox: `terrain.gd` declares `field: HeightField` and `material: Material`; `sandbox.tscn` assigns `data/terrain/sandbox_height_field.tres` and `data/terrain/terrain_material.tres`.

Ways to swap an asset:

1. Export over the same filename in `game/assets/`. Godot reimports when its window regains focus, and every reference updates. Nothing else changes.
2. Point a Data resource at a different file. One field edit in the Inspector.
3. Make a variant. Duplicate a `.tres`, change its values, assign it in a scene.

Naming: `<category>_<name>_<variant>.<ext>`, lower case with underscores.
Examples: `tex_granite_albedo.png`, `tex_granite_normal.png`, `sfx_step_gravel_03.wav`, `ir_canyon_small.wav`.

## Version control

Binary sources and exports enlarge the repository with every revision. Git LFS is installed on the development machine (`/opt/homebrew/bin/git-lfs`). The following `.gitattributes` is recommended once the first binary asset is committed; it has not been added yet because it changes how the remote stores files.

```
*.png       filter=lfs diff=lfs merge=lfs -text
*.wav       filter=lfs diff=lfs merge=lfs -text
*.ogg       filter=lfs diff=lfs merge=lfs -text
*.glb       filter=lfs diff=lfs merge=lfs -text
*.procreate filter=lfs diff=lfs merge=lfs -text
*.als       filter=lfs diff=lfs merge=lfs -text
*.blend     filter=lfs diff=lfs merge=lfs -text
```

Godot writes a `.import` file beside each imported asset and a `.uid` file beside each script and shader. Both belong in Git: `.import` stores import settings, `.uid` stores the stable identifier other files use to reference the script. The cache directory `game/.godot/` does not (see `.gitignore`).

## Consequences

- Procedural content (terrain, SDF rocks, synthesized sound) has no export layer. Its Data resource is the asset.
- Lesson 30 builds an asset registry and runtime hot-reload on this layout. Lesson 31 adds editor tools.
