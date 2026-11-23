// osc_roundtrip_listener.scd
// Receiving half of tools/osc_roundtrip.sh. Run by sclang in batch mode;
// the sending half is tools/godot/osc_send.gd, run by Godot.
//
// Prints "PORT <n>" once it listens, so the shell script knows where
// Godot must send. Then it waits for the messages osc_send.gd sends,
// compares each with the expected values, and exits:
//   exit 0  every expected message arrived with the expected values
//   exit 1  a message differed, or not all arrived within 10 seconds
// It does not boot the server.

(
var expected, received, check, finish;
// Q: Why compare floats with a tolerance?
// A: Godot sends float32. 1.234 becomes 1.2339999675751 on the way,
//    so an exact comparison with the literal 1.234 fails.
expected = (
	'/roundtrip/types': [1000, -1, \hello, 1.234],
	'/player/state': [1.5, -2.25, 3.0, 0.75, 1],
	'/player/ground': [\steep]
);
received = IdentityDictionary.new;
check = { |want, got|
	(want.size == got.size) and: {
		want.every { |w, i|
			if(w.isKindOf(Float)) { (w - got[i]).abs < 1e-6 } { w == got[i] }
		}
	}
};
finish = { |code|
	"RESULT % of % messages matched".format(
		received.count { |ok| ok }, expected.size
	).postln;
	OSCdef.freeAll;
	code.exit;
};
expected.keysDo { |address|
	OSCdef(address, { |msg|
		var ok;
		ok = check.(expected[address], msg[1..]);
		"RECV % % %".format(msg, msg[1..].collect(_.class), if(ok) { "ok" } { "MISMATCH" }).postln;
		received[address] = ok;
		if(received.size == expected.size) {
			AppClock.sched(0, { finish.(if(received.every(_.value)) { 0 } { 1 }); nil });
		};
	}, address);
};
"PORT %".format(NetAddr.langPort).postln;
AppClock.sched(10, { "TIMEOUT".postln; finish.(1); nil });
)
