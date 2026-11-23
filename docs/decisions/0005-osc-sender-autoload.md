# 0005. OSC sender as an autoload; own encoder; fixed Lesson 04 addresses

Status: accepted, 2026-11-22 (Lesson 04).

## Context

Decision 0003 places SuperCollider in a separate process that receives OSC over UDP. Lesson 04 implements the Godot side. Three choices arise: where the socket lives, how messages become bytes, and what the first addresses carry.

## Decision

1. **One socket in an autoload.** `game/src/audio/osc_sender.gd` (`OscSender`) is registered in `project.godot` as the autoload `Osc`. Every scene reaches it as `/root/Osc`. It sends nothing on its own; scenes before Lesson 04 have no caller and stay silent (checked in `tests/test_04_osc_sender.gd`).
2. **Unconnected UDP socket.** The sender uses `PacketPeerUDP.set_dest_address()`, not `connect_to_host()`. Measured in Godot 4.6.2 on macOS with no listener on the port: `set_dest_address()` returns `OK` on every `put_packet()`; after `connect_to_host()`, every second `put_packet()` returns `FAILED` (ICMP port-unreachable reported back to the connected socket).
3. **Own encoder.** `game/src/audio/osc_encoder.gd` (`OscEncoder`) writes OSC 1.0 messages with types `i`, `f`, `s`. No addon. The encoder is short and is lesson material; a test compares it byte for byte with hand-written arrays.
4. **State is sent from `_physics_process()` through a rate clock** (`game/src/audio/rate_clock.gd`), default 30 Hz, independent of the physics tick rate.
5. **Addresses of Lesson 04:**

| Address | Types | Arguments | When |
|---|---|---|---|
| `/player/state` | `ffffi` | x, y, z (m, capsule center), horizontal speed (m/s), ground state (0 floor, 1 steep, 2 air) | `send_rate_hz` times per second |
| `/player/ground` | `s` | `floor`, `steep`, or `air` | on change, and once at startup |

`balance` and `stance` from decision 0003's example join `/player/state` in Lessons 13–14 as further arguments appended at the end, so receivers that read the first five keep working.

## Consequences

- No return channel yet: nothing in Godot listens on port 9000. Lesson 04 exercise E5 builds a receiver; a starter-code receiver arrives with the first lesson that needs SuperCollider → Godot messages.
- No bundles or timetags; Lesson 05 adds them for footstep events.
- Tests redirect the autoload with `Osc.set_destination()` to a local socket and restore it afterwards.
- A running SuperCollider on port 57120 receives messages from every run of the Lesson 04 scene, including `tools/check.sh` runs.
