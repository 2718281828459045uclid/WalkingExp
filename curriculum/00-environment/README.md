# Lesson 00. Environment and editor tour

## 1. Orientation

This lesson opens the project, maps the editor onto the files on disk, and confirms that the controller and SuperCollider work. No new code is written.

Goal served (`plan.md`): "a robust editing interface that separates code and assets."

Files: `game/project.godot`, `game/scenes/sandbox.tscn`, `game/scenes/player.tscn`, `game/data/terrain/*.tres`, `audio/supercollider/00_osc_monitor.scd`.

## 2. Predict

Answer before opening the project.

- **P1.** A Godot game is a tree of *nodes*. A *scene* is a saved subtree. Do you expect a scene to be stored as binary data, as text, or as code?
- **P2.** The sandbox shows a terrain of 16,641 vertices. Open `game/scenes/sandbox.tscn` in a text editor. It contains no vertex data. Form a hypothesis for where the vertices come from.
- **P3.** Godot must know which scene to run first and which keys mean "move forward." Where might that information live?
- **P4.** Godot uses three words that are easy to confuse: *Node*, *Scene*, *Resource*. Guess the difference from the file extensions `.tscn` and `.tres` and the folder names `scenes/` and `data/`.

## 3. Read

### 3.1 Open the project

1. Start Godot 4.6.2. In the Project Manager choose **Import**, select `game/project.godot`, then **Open**.
2. The first open imports the project and creates `game/.godot/` (a cache; ignored by Git).
3. Locate the five editor areas:
   - **Scene dock** (top left): the node tree of the open scene.
   - **FileSystem dock** (bottom left): the contents of `game/`, shown as `res://`.
   - **Viewport** (center): 3D view of the open scene.
   - **Inspector** (right): properties of the selected node or resource.
   - **Output panel** (bottom): print statements and errors.

### 3.2 Map the editor to the files

Open `res://scenes/sandbox.tscn` in the editor and in a text editor side by side.

| In the text file | In the editor |
|---|---|
| `[ext_resource ...]` | A reference to another file (script, resource, scene) |
| `[sub_resource ...]` | A resource stored inside this scene file (the sky, the environment) |
| `[node name="Terrain" ... parent="."]` | A row in the Scene dock |
| `field = ExtResource("3_field")` | A property in the Inspector that points at a file |
| `instance=ExtResource("5_player")` | A scene placed inside another scene (the Player) |

Now open `game/project.godot` in a text editor. Find the main scene, the `[input]` section, and the physics engine. Check P3.

Read the comment block at the top of `game/src/terrain/terrain.gd`. Check P2.

## 4. Run and observe

Controls are listed in the repository `README.md`.

- **O1.** Open `res://scenes/sandbox.tscn` and press F6 (Run Current Scene). F5 runs the project's main scene instead, which is the newest lesson's scene (see `curriculum/README.md`). Walk to the top of the central hill. Press Tab to cycle the terrain views and N to cycle normal methods. Note what changes on screen for each. (Lesson 01 explains them.)
- **O2.** Stop the game. Select the `Terrain` node. In the Inspector, expand **Field** and drag **Mound Height**. Watch the viewport. Save (Cmd+S), then run `git status` in a terminal. Which file changed: the scene or the `.tres`? Why?
- **O3.** Run the game again. In the Scene dock, switch from **Local** to **Remote** (tabs at the top of the dock). Select `Player` and change **Walk Speed** while walking. Stop the game. Is the new value still there?
- **O4.** With a gamepad connected, push the left stick a quarter, half, and all the way. Does speed scale with deflection? Is there a dead region near the center? Note your observations for Lesson 14.
- **O5.** Select the `Sun` node and rotate it in the viewport. What happens to the rock-colored areas of the terrain? (They do not move. Why not?)

## 5. Tweak

- **T1.** Duplicate `data/terrain/sandbox_height_field.tres` in the FileSystem dock (right click, **Duplicate**). Change its values. Drag the new file onto the Terrain's **Field** property. Switch back and forth. This is the asset-swap workflow from `docs/decisions/0004-asset-pipeline.md`.
- **T2.** Open **Project → Project Settings → Input Map**. Add an action `lesson00_probe` bound to the H key and to the gamepad's south button (A / Cross). Save, then run `git diff game/project.godot` and find your change in the text. In `sandbox.gd`, add one `elif` branch to `_unhandled_input` that prints a line when the action is pressed, and run the sandbox to confirm it. Remove the action and the branch afterward; no later lesson uses them.

## 6. Exercises

- **E1 ★** External editor. Install VS Code and the "godot-tools" extension. In Godot: **Editor → Editor Settings → Text Editor → External**, enable **Use External Editor**, set **Exec Path** to VS Code and **Exec Flags** to `{project} --goto {file}:{line}:{col}`. Confirm that double-clicking a script opens it in VS Code with completion working (the extension connects to Godot's language server on port 6005 while the editor is open).
- **E2 ★** Shell alias. Add `alias godot="/Applications/Godot.app/Contents/MacOS/Godot"` to `~/.zshrc`. Run the headless check from the repository `README.md`. Then introduce a deliberate syntax error in `player.gd` and run it again. Read the error output: which file and line does it name?
- **E3 ★** SuperCollider listener. Open `audio/supercollider/00_osc_monitor.scd`, boot the server, run the first block. Note the port printed in the post window. Lesson 04 sends game data to that port.

## 7. Reflect

- **R1.** The terrain is built by code at load time; its parameters are stored in a `.tres` file. What are the costs and benefits compared with saving the mesh itself as an asset?
- **R2.** You will create textures in Procreate and samples in Ableton Live. Following decision 0004, trace the path of one texture from a `.procreate` file to a pixel on screen. Name every folder and file type it passes through.

## 8. Answers

<details><summary>P1</summary>

Text. `.tscn` (text scene) files list resources and nodes in an INI-like format. This makes them readable in Git diffs. Godot can also save binary `.scn` files; this project does not use them.
</details>

<details><summary>P2</summary>

`terrain.gd` generates the vertices in `_ready()` from the `HeightField` resource and adds them through an *internal* child node, which Godot does not save. The scene stores only the parameters, through the reference to `sandbox_height_field.tres`.
</details>

<details><summary>P3</summary>

`game/project.godot`: `run/main_scene` under `[application]`, and one entry per action under `[input]`. The `[input]` entries are verbose because Godot serializes each input event as an object. Editing them through **Project Settings → Input Map** is the normal route.
</details>

<details><summary>P4</summary>

- A **Node** is one object in the running tree (a light, a mesh instance, a physics body). Nodes have position in the tree and receive callbacks such as `_ready()` and `_physics_process()`.
- A **Scene** is a saved tree of nodes (`.tscn`). Scenes can be placed inside other scenes (the Player inside the Sandbox).
- A **Resource** is a data object that is not in the tree: a mesh, a material, a texture, a set of parameters (`.tres`). Several nodes can share one Resource. In this project, `data/` holds Resources that describe *what* (parameters, assets); `scenes/` holds trees that describe *where and how* things are assembled.
</details>

<details><summary>O2</summary>

The `.tres` file changed, not the scene. The scene holds a reference to the resource; the values live in the resource file. Editing a shared resource changes it for every scene that uses it. To change one scene's terrain without affecting others, assign a duplicate (T1).
</details>

<details><summary>O3</summary>

No. The Remote tree edits the running game process. Nothing is written to disk. It is a tool for tuning: find a good value while playing, then type it into the Local scene.
</details>

<details><summary>O5</summary>

The rock coloring depends on the surface normal alone (`slope_degrees` in `terrain.gdshader`), not on the light direction. Light changes the brightness of every surface; the material assignment does not move. Lesson 17 replaces Godot's lighting function and makes the relationship between normal and light explicit.
</details>
