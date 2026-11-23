# Lesson 04. OSC from Godot to SuperCollider

Lesson scene: `game/scenes/lessons/04_osc_bridge.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–03 are unchanged and send nothing.

## 1. Orientation

Until now the game has had no sound and no connection to anything outside Godot. This lesson builds the first half of the audio architecture of decision 0003: Godot describes the player in Open Sound Control (OSC) messages and sends them over UDP to sclang, which prints them. No synth plays yet. The lesson answers four questions:

1. What exactly is an OSC message, byte by byte? (encoding)
2. How does a packet get from one program to another on the same machine, and what happens when nobody listens? (UDP)
3. How often should continuous state go out, and how is that rate kept independent of the physics tick rate? (rate clock)
4. Where in a Godot project does a service that every scene can use belong? (autoload)

Goal served (`plan.md`): "music and audio that is primarily diegetic and interactive/generative"; "the player's movements and environment influence the audio as well as the composition."

Files:

| File | Role |
|---|---|
| `game/src/audio/osc_encoder.gd` | `OscEncoder`: static functions that turn an address and arguments into OSC 1.0 bytes. Types `i`, `f`, `s`. |
| `game/src/audio/osc_sender.gd` | `OscSender` (Node): one UDP socket, `send(address, args)`, counters. Registered as the autoload `Osc`. |
| `game/src/audio/rate_clock.gd` | `RateClock`: decides on which physics ticks a message at a given rate is due. |
| `game/src/audio/player_state_reporter.gd` | `PlayerStateReporter` (Node): reads the `Player`, sends `/player/state` at `send_rate_hz` and `/player/ground` on change. |
| `game/src/lessons/osc_bridge.gd` | Scene root. Extends `painting_the_ground.gd` (Lesson 03); adds the O key and HUD lines. |
| `game/scenes/lessons/04_osc_bridge.tscn` | The Lesson 03 scene's WorldEnvironment, Sun, Terrain, ColorStrip, and Player, a HUD at the top left, and a `StateReporter` node. No `RampTower`. |
| `game/project.godot` | Autoload `Osc`; input action `cycle_osc_rate` (O, gamepad X). `run/main_scene` pointed to this scene while it was the newest lesson scene. |
| `audio/supercollider/04_player_state.scd` | OSCdefs that receive both addresses and print the state twice per second. |
| `tools/sc_check.sh`, `tools/sc/check_syntax.scd` | Syntax check of every `.scd` code block in sclang batch mode. |
| `tools/osc_roundtrip.sh`, `tools/sc/osc_roundtrip_listener.scd`, `tools/godot/osc_send.gd` | Round-trip test: Godot sends three messages, sclang checks what arrives. |
| `game/tests/test_04_*.gd` | Byte-exact encoder tests; rate clock, loopback, and scene tests. |
| `docs/decisions/0005-osc-sender-autoload.md` | Why an autoload, why an unconnected socket, which addresses. |

Reading: the Open Sound Control 1.0 specification (one page; read "OSC Packets", "OSC Messages", "OSC Type Tag String", "Atomic Data Types"). Godot class reference: `PacketPeerUDP` (`set_dest_address`, `put_packet`, `bind`), `StreamPeerBuffer` (`big_endian`, `put_32`, `put_float`), and the manual page "Singletons (Autoload)". SuperCollider help: "OSC Communication", `OSCdef`, `NetAddr`. Full entries: `docs/references.md`. This lesson has no geometry; there is no DDG reading.

Lesson 00 checked that sclang listens on port 57120 (`audio/supercollider/00_osc_monitor.scd`). This lesson sends to that port.

## 2. Predict

Work these on paper before reading the code. You need two facts from the OSC 1.0 specification: every part of a message (address, type tag string, each argument) occupies a multiple of 4 bytes, and numbers are big-endian (most significant byte first).

- **P1.** A string in OSC is its ASCII bytes followed by zero bytes up to the next multiple of 4, with at least one zero byte. Give the padded length for strings of 0 to 8 characters. Write a formula in terms of the integer division n / 4. Why must "/abc" take 8 bytes and not 4?
- **P2.** Write out, in hexadecimal, every byte of the message with address `/a` and no arguments. (A message without arguments still has a type tag string.)
- **P3.** The message `/player/state` carries four floats and one int. How many bytes is it? How many bytes is `/player/ground` with the argument `floor`? With `air`?
- **P4.** Write the four big-endian bytes of the int32 values 1000, −1, and 57120. Then the float32 values 1.5, −2.25, and 440.0: find the sign bit, the biased exponent (bias 127), and the 23 fraction bits of each.
- **P5.** Godot stores 1.234 in a 64-bit float. The encoder writes 32 bits, and sclang reads them into its own 64-bit Float. What value does sclang print? Is 1.234 == the received value?
- **P6.** At 30 messages per second, how many bytes per second does `/player/state` produce? Each UDP datagram over IPv4 adds an 8-byte UDP header and a 20-byte IP header. What is the total? Compare with a 44.1 kHz mono 16-bit audio stream.
- **P7.** The reporter adds each tick's Δt to an accumulator and sends when it reaches 1/30 s, subtracting 1/30 each time. With 60 physics ticks per second, on which ticks does it send? With 144 ticks per second, how many ticks lie between sends, and how often does each spacing occur per second? What is the largest delay between the ideal send time and the actual one?
- **P8.** SuperCollider is not running. The game sends a UDP packet to 127.0.0.1:57120. What happens to the packet? Does the game learn about it? What would TCP do instead?

## 3. Read

### 3.1 `osc_encoder.gd`

Read the layout diagram in the header comment, then `encode_message()`. The function writes into a `StreamPeerBuffer`, a byte array with a write position. Find the line that sets `big_endian`. What would happen without it on an Apple M1 or an x86 PC, both of which are little-endian?

`padded_string()` and `padded_length()` implement P1. `type_tags()` builds the type tag string from the GDScript types of the arguments: `int` → `i`, `float` → `f`, `String` and `StringName` → `s`. Which GDScript type does the literal `3` have, and which does `3.0` have? What type tag would `[1, 2, 3]` produce, and is that what a receiver expecting positions wants?

The encoder handles three of the OSC 1.0 types. The fourth required type, the blob (`b`), is exercise E1.

### 3.2 `osc_sender.gd` and the autoload

Open **Project → Project Settings → Globals → Autoload**. The entry `Osc` points to `src/audio/osc_sender.gd`. Godot creates one instance of the script at startup, adds it to the tree as `/root/Osc` before the main scene, and keeps it while scenes change. The `*` in front of the path in `project.godot` makes the name a global: scripts can write `Osc.send(...)`.

Read the Q/A comments in `set_destination()` and at the top of the file. The sender uses `set_dest_address()`, not `connect_to_host()`. Decision 0005 records the measurement that led to this choice.

`send()` returns `true` when the operating system accepted the packet. What does `true` not tell you?

### 3.3 `rate_clock.gd`

The diagram in the header comment shows P7. `tick(delta)` contains two Q/A comments: one about a floating-point tolerance, one about a frame hitch. Compare the hitch rule with the way Godot itself runs physics: after a long frame, Godot runs several physics ticks in a row (up to `physics/common/max_physics_steps_per_frame`, default 8) to catch up. Each of those ticks calls `tick(1/60)`, not `tick(0.5)`. Which of the two cases produces two sends a fraction of a millisecond apart? Keep the answer for O5.

### 3.4 `player_state_reporter.gd`

Two message classes from decision 0003 meet here. `/player/state` is continuous: it goes out at a fixed rate whether or not anything changed. `/player/ground` is an event: it goes out when the ground state changes. `state_arguments()` is static and returns the argument array; the Q/A comment explains the explicit `float()` and `int()` conversions.

`_ready()` takes the `Osc` autoload unless someone assigned `sender` before. Find where the test assigns nothing and instead redirects the autoload.

### 3.5 `osc_bridge.gd` and the scene

The scene keeps the Lesson 03 scene's WorldEnvironment, Sun, Terrain, ColorStrip, and Player. It leaves out the `RampTower`, which served Lesson 03 O3; the root's `ramp_tower` property stays empty, so the placement step skips it (Q/A comment in `_ready()` of `painting_the_ground.gd`). The HUD sits at the top left. One node is new: `StateReporter`, whose `player` property points at `../Player`. The root script extends `painting_the_ground.gd`, so V, C, M, F, Tab and N still work. It adds the O key and two HUD lines: destination, rate, totals, and the traffic of the last full second.

### 3.6 `04_player_state.scd`

Block 1 creates an Event `~player` and two OSCdefs. An `OSCdef` is a named responder: running the block again replaces the responder of the same name instead of adding a second one. The function receives `msg`, an Array whose first element is the address. Note the comment on strings: OSC strings arrive in sclang as Symbols. Block 2 is a Routine that prints the state twice per second. Block 3 removes both.

The file follows a convention that `tools/sc_check.sh` relies on: a block opens with a line holding only `(` and closes with a line holding only `)`. Read the Q/A comment at the top of `tools/sc/check_syntax.scd` for the reason.

### 3.7 The tools

`tools/sc_check.sh` compiles every block of every `.scd` file without running it. `tools/osc_roundtrip.sh` starts sclang with `tools/sc/osc_roundtrip_listener.scd` in the background, waits for its `PORT` line, runs `tools/godot/osc_send.gd` with that port, and reports what sclang received. Both shell scripts give sclang `/dev/null` as standard input; the header of `sc_check.sh` says why.

## 4. Run and observe

Start SuperCollider (the IDE). Open `audio/supercollider/04_player_state.scd`, run block 1 (cursor inside, Cmd-Return), then block 2. Do not boot the server; nothing here needs it. Then open the lesson scene in Godot and press F6. **O** (gamepad X) cycles the state rate: 30 → 60 → off → 10 → 30 Hz.

- **O1.** Read the post window. Which values change as you walk? Walk up a slope and watch y. Stand still: does the speed reach exactly 0, and how fast?
- **O2.** Read the HUD's `msg/s` and `B/s` at each rate. Compare with P6. Why is `msg/s` at "off" not always 0 at the moment you switch?
- **O3.** Stop the Godot scene, then start it again. What does the post window print first? Then stop SuperCollider's responders (block 3) while the game runs, and run block 1 again. What does `~player.groundName` hold until you next step from floor to steep ground? What does this say about sending events only on change?
- **O4.** Run the first block of `00_osc_monitor.scd` (`OSCFunc.trace`). Read one raw `/player/state` message. Which entries tell you where the packet came from? Run `OSCFunc.trace(false)` afterwards.
- **O5.** Block 2 prints `last interval` in milliseconds: the arrival time difference between the last two `/player/state` messages. Watch it for a minute at 30 Hz. What range do you see, and do values near 0 ms appear? Compare with the answer you kept from §3.3.
- **O6.** Quit SuperCollider entirely while the game runs. Does Godot print an error? Does the HUD's message count stop?
- **O7.** In a terminal, run `tools/osc_roundtrip.sh`. Read the `RECV` lines. Which class does sclang give each argument, and how does it print 1.234? Compare with P5. If the IDE is open, which port does the listener report?
- **O8.** Restart the scene and read the first `ground:` lines: the capsule spawns above the ground, so the `air` state appears before the first landing. Then walk onto the steep hill until you slide, and walk back to flat ground. How many `ground:` lines does one slide produce?

## 5. Tweak

Restore each change after the observation.

- **T1.** Select **StateReporter** in the lesson scene and set **Send Rate Hz** to 240. Run with the default 60 physics ticks. What rate arrives? What rate arrives with 144 ticks (`physics/common/physics_ticks_per_second`)? Why can the clock never exceed the tick rate?
- **T2.** In `osc_encoder.gd`, comment out `buffer.big_endian = true` and run `tools/osc_roundtrip.sh`. Predict before running: what does sclang print for 1000, −1, `hello`, and 1.234? Which values survive and why?
- **T3.** In `osc_sender.gd`, replace `_socket.set_dest_address(host, port)` with `_socket.connect_to_host(host, port)`. Quit SuperCollider and run the scene. Watch the HUD's message count against the elapsed time. What fraction of sends fails?
- **T4.** In `state_arguments()`, remove the `float()` around `p.x` and replace it with `int(p.x)`. What does the type tag string become, and what does `04_player_state.scd` print for x? Does anything on the SuperCollider side fail?
- **T5.** In `rate_clock.gd`, change `1e-9` to `0.0` and run `test_04_osc_sender.gd`. Which tick rate fails? Then also change the comparison from `<` to `<=` and run the test again. Which tick rate suffers most, and why that one?
- **T6.** Change the address `/player/state` in `player_state_reporter.gd` to `/player/State`. What does sclang do with the message? Run `OSCFunc.trace` to see whether it arrives.

## 6. Exercises

- **E1 ★ Blobs.** Add the OSC 1.0 blob type `b` to `OscEncoder` for `PackedByteArray` arguments: an int32 byte count, the bytes, then zero padding to a multiple of 4. Write the expected bytes of a 5-byte blob by hand first. Test in your own SceneTree script in the lesson folder; confirm in sclang that the argument arrives as an `Int8Array`.
- **E2 ★ Dead band.** At rest, `/player/state` repeats the same values 30 times per second. Send only when the position moved more than a threshold or the speed changed more than another, and send at least once per second regardless (a keep-alive). Choose the thresholds from measurements and count the messages saved on a walk with pauses.
- **E3 ★ A probe without Godot.** Write `tools/osc_probe.py` with Python's `socket` and `struct` modules: send a `/player/state` message with values given on the command line, and print any packet received on a port given with `--listen`. Compare its bytes with `OscEncoder` for the same values.
- **E4 ★★ First sound.** Boot the server in your own SuperCollider session and write a SynthDef whose amplitude and filter cutoff follow the player's speed, set from the `/player/state` OSCdef. At 30 Hz the control value jumps every 33 ms. Listen for zipper noise, then remove it with `Lag` or `VarLag`. Which lag time hides the steps without making the sound lag behind the walk?
- **E5 ★★ The return channel.** Decision 0003 reserves UDP port 9000 for SuperCollider → Godot. Write an `OscDecoder` (the inverse of `OscEncoder`) and a node that binds port 9000 and calls a function per received address. In sclang, reply to every `/player/ground` with `/echo/ground`. Measure the round-trip time Godot → sclang → Godot with `Time.get_ticks_usec()` over 1000 messages and report the median and the 99th percentile.
- **E6 ★★★ Address patterns.** OSC 1.0 lets a receiver's address be matched by patterns: `?`, `*`, `[abc]`, `[a-z]`, `{foo,bar}`. Extend your E5 receiver so a handler can register a pattern such as `/music/{beat,section}`. Write tests from the specification's rules before the matcher.

## 7. Reflect

- **R1.** UDP may drop, duplicate, or reorder packets; TCP delivers a stream in order and retransmits. For `/player/state`, which failure costs more: a lost packet or one delivered 200 ms late? For a footstep event? Which transport would you pick for each?
- **R2.** `/player/state` is a sampled signal at 30 Hz. By the sampling theorem, what is the highest frequency of player motion SuperCollider can reconstruct? Is that enough for walking (about 2 steps per second)? For the balance wobble of Lesson 13?
- **R3.** O5 shows the arrival intervals scatter around 33 ms. For a drone that follows speed, does that matter? For footsteps triggered on arrival (Lesson 05), it does. Lesson 05 stamps events with a time and lets SuperCollider schedule them. What must both sides agree on for that to work?
- **R4.** The autoload is global state: any script can call `Osc.send()`. What are the benefits for a sender? What would make a global receiver (E5) harder to reason about than a global sender?
- **R5.** `/player/ground` sends the names `floor`, `steep`, `air`; `/player/state` sends the same information as 0, 1, 2. Which form is better for a SuperCollider `switch`, which for a human reading `OSCFunc.trace`, and which would break if a later lesson inserted a state, such as crawling, in the middle of the enum? (Lesson 16 sends its postures in a message of their own, `/body/posture`.)

## 8. Answers

<details><summary>P1</summary>

Padded length = (n / 4 + 1) · 4 with integer division: 4, 4, 4, 4, 8, 8, 8, 8, 12 for n = 0 … 8. The zero byte terminates the string; a reader scans to the first zero, then skips to the next multiple of 4. "/abc" without a zero would run into the type tag string, so it gets four zeros. `test_04_osc_encoder.gd` checks the nine values.
</details>

<details><summary>P2</summary>

`2f 61 00 00 2c 00 00 00`: "/a" plus two zeros, then "," plus three zeros. 8 bytes.
</details>

<details><summary>P3</summary>

`/player/state`: 13 characters → 16 bytes; `,ffffi` 6 characters → 8 bytes; five arguments × 4 = 20 bytes. Total 44. `/player/ground` with `floor`: 14 → 16, `,s` → 4, `floor` (5) → 8. Total 28. With `air`: 16 + 4 + 4 = 24. The encoder test checks 44; the loopback test checks that 44 bytes arrive.
</details>

<details><summary>P4</summary>

| Value | Bytes |
|---|---|
| 1000 | `00 00 03 e8` |
| −1 | `ff ff ff ff` (two's complement) |
| 57120 | `00 00 df 20` |
| 1.5 = 1.1₂ × 2⁰ | sign 0, exponent 127, fraction 100…: `3f c0 00 00` |
| −2.25 = −1.001₂ × 2¹ | sign 1, exponent 128, fraction 001…: `c0 10 00 00` |
| 440 = 1.10111₂ × 2⁸ | sign 0, exponent 135, fraction 10111…: `43 dc 00 00` |

The values were checked with Python's `struct.pack('>i' / '>f')`; 1000, −1, and 440.0 also appear in `test_04_osc_encoder.gd`.
</details>

<details><summary>P5</summary>

The nearest float32 to 1.234 is 1.2339999675750732. sclang prints it as `1.2339999675751` (O7). 1.234 == that value is false; the round-trip listener compares with a tolerance of 10⁻⁶ for this reason.
</details>

<details><summary>P6</summary>

44 × 30 = 1320 B/s of OSC. With 28 bytes of headers: 72 × 30 = 2160 B/s. A 44.1 kHz 16-bit mono stream is 88 200 B/s, about 40 times more. The HUD reads 1320 B/s at 30 Hz (it counts OSC bytes, not headers).
</details>

<details><summary>P7</summary>

At 60 Hz: every second tick, exactly (1/60 + 1/60 = 1/30 holds in binary floating point). At 144 Hz: a period is 4.8 ticks, so sends are 4 or 5 ticks apart (the test checks that no other spacing occurs). Per second, 30 sends fill 144 ticks: a + b = 30 and 5a + 4b = 144 give 24 gaps of 5 ticks and 6 gaps of 4. A send happens on the first tick at or after its ideal time, so it is late by less than one tick: up to 6.9 ms at 144 Hz.
</details>

<details><summary>P8</summary>

The kernel finds no socket bound to port 57120 and drops the packet; on loopback it may answer with an ICMP "port unreachable" message. With an unconnected socket (`set_dest_address()`) the game never sees that message: `put_packet()` returned `OK` on 20 sends to a closed port in `test_04_osc_sender.gd`. TCP would first need a connection; with no listener, the connection attempt is refused and the game would have to handle the error and retry.
</details>

<details><summary>O2</summary>

The HUD reads 30 msg/s and 1320 B/s at 30 Hz; 60 and 2640 at 60 Hz; 10 and 440 at 10 Hz. `/player/ground` messages add 24 or 28 bytes when the ground state changes. The counts cover the last full second, so the readout lags a change of rate by up to one second.
</details>

<details><summary>O3</summary>

On restart, the first line is `ground: air`: the capsule spawns 1 m above the ground, the reporter sends the initial state, and `ground: floor` follows when the capsule lands. After block 1 runs again, `~player.groundName` holds `air` (the default in block 1) until the next change, while the capsule stands on the floor. A receiver that joins late misses every event sent before it joined; continuous state repairs itself within one period. Lesson 05 returns to this.
</details>

<details><summary>O5</summary>

Measured with a sclang listener over 4 s (120 messages) while the lesson scene ran:

| Run | Mean | Most intervals | Near 0 ms |
|---|---|---|---|
| Windowed, 60 Hz ticks, 60 fps | 31.7 ms | 28–39 ms | 6 of 119 below 2 ms |
| Headless, 60 Hz ticks | 31.8 ms | 25–40 ms | 6 of 119 below 2 ms |
| Headless, 144 Hz ticks | 32.8 ms | 26–39 ms | 2 of 119 below 3 ms |

The near-zero intervals come from Godot's catch-up: after a long frame (scene load) it runs several physics ticks back to back, each with Δt = 1/60, so the rate clock sends on two of them within a fraction of a millisecond. The scatter of several milliseconds around 33 ms comes from the frame loop: physics ticks run at the start of a frame, not at evenly spaced times. The mean is below 33.3 ms because the window starts with the catch-up burst.
</details>

<details><summary>O6</summary>

No error, and the count keeps rising (decision 0005; `set_dest_address()`). The packets are dropped by the system.
</details>

<details><summary>O7</summary>

```
RECV [ /roundtrip/types, 1000, -1, hello, 1.2339999675751 ] [ class Integer, class Integer, class Symbol, class Float ] ok
RECV [ /player/state, 1.5, -2.25, 3.0, 0.75, 1 ] [ class Float, class Float, class Float, class Float, class Integer ] ok
RECV [ /player/ground, steep ] [ class Symbol ] ok
```

Godot reports `sent 3 messages, 120 bytes` (48 + 44 + 28). With the IDE's sclang holding 57120, the batch sclang reports 57121 and the script sends there.
</details>

<details><summary>T1</summary>

60 messages per second at 60 Hz ticks, 144 at 144 Hz: `tick()` returns `true` at most once per call, and it is called once per physics tick. The test checks 60 sends per second for a 240 Hz clock on 60 Hz ticks.
</details>

<details><summary>T2</summary>

The bytes of each number are reversed. 1000 (`e8 03 00 00` read big-endian) arrives as −402456576. −1 survives: all four bytes are `ff`. `hello` and the address survive: strings are byte sequences with no byte order. 1.234 arrives as about −7.26 × 10⁻⁶; 1.5 arrives as 6.9 × 10⁻⁴¹, a denormal. The listener reports a mismatch on all three messages. (Values computed by reversing the bytes with Python's `struct`.)
</details>

<details><summary>T3</summary>

Measured in a probe script with no listener: after `connect_to_host()`, `put_packet()` alternates between `OK` and `FAILED`, so half the sends fail and the HUD count rises at half the rate. The ICMP reply to one packet makes the next send fail.
</details>

<details><summary>T4</summary>

The type tag string becomes `,iffi`; sclang prints x as an Integer (the coordinate truncated toward zero). Nothing fails: OSCdef does not check types. A receiver that divides x by 2 now gets integer division in some languages, not in sclang. Type tags are documentation the receiver may ignore.
</details>

<details><summary>T5</summary>

With tolerance 0, the 144 Hz case fails: 299 sends in 10 s instead of 300. With tolerance 0 and `<=`, measured over 10 simulated seconds: 150 sends at 30 Hz ticks, 300 at 60 Hz, 299 at 144 Hz, 299 at 240 Hz. At 30 Hz ticks every tick brings the accumulator to exactly one period, `<=` makes it wait, and only every second tick sends. At 60 Hz the rounded sums land just above the period, so `<=` changes nothing there; the result depends on rounding, which is the reason for an explicit tolerance.
</details>

<details><summary>T6</summary>

OSC addresses are case-sensitive. The message arrives (`OSCFunc.trace` shows it), but no OSCdef matches `/player/State`, so the state stops updating without any error on either side.
</details>
