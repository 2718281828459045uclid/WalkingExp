// 00_osc_monitor.scd
// Prints every OSC message that reaches sclang.
// Lesson 00: confirm the port. Lesson 04: watch the messages Godot sends.

(
NetAddr.langPort.postln;    // Godot sends to this port (default 57120)
OSCFunc.trace(true, true);  // second argument hides /status.reply messages from scsynth
)

// Stop printing.
OSCFunc.trace(false);
