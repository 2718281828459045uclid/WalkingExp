# Exported assets

Files in this folder are written by export from the tools in `art-source/`. Godot imports them and writes a `.import` file beside each one; commit the `.import` files.

| Folder | Contents | Import notes |
|---|---|---|
| `textures/` | `.png` | Normal maps: set **Compress → Normal Map** in the Import dock. |
| `audio/samples/` | `.wav` (short sounds), `.ogg` (long loops) | Set loop points in the Import dock, not in code. |
| `audio/ir/` | Impulse responses for convolution reverb | Loaded by SuperCollider, not by Godot. |
| `meshes/` | `.glb` | Rocks and terrain are procedural; this folder is for props. |
| `fonts/` | `.ttf`, `.otf` | Used by UI themes (Lesson 33). |

Naming: `<category>_<name>_<variant>.<ext>`, for example `tex_granite_normal.png`, `sfx_step_gravel_03.wav`.

Code does not reference these files by path. Resources in `game/data/` reference them, and scripts receive those Resources through exported properties (decision 0004).
