// 13_balance.scd
// Receives the balance of the body (Lesson 13).
// Sender: game/src/body/balance_monitor.gd, through the "Osc" autoload.
// Message layout:
//   /body/balance        margin state x z height
//                        (Float m, Integer 0 none / 1 stable / 2 marginal /
//                         3 outside, Float x3 m), 30 per second
//   /body/balance/state  name   (sent on change: none, stable, marginal, outside)
//
// Block 1 uses sclang only. Blocks 2 and 3 need the server, booted by you.
// Run block 1, then start game/scenes/lessons/13_balance.tscn (F6).


// 1. Responders. The latest values go into ~balance; state changes print.
(
~balance = (margin: 0, state: 0, x: 0, z: 0, height: 0, changes: 0, voice: nil);

OSCdef(\bodyBalance, { |msg|
	// msg: [ '/body/balance', margin, state, x, z, height ]
	~balance.margin = msg[1];
	~balance.state = msg[2];
	~balance.x = msg[3];
	~balance.z = msg[4];
	~balance.height = msg[5];
	// Q: Why test for the voice here, in the responder?
	// A: Block 1 runs without a server. The synth exists only after
	//    block 3; until then the responder only stores the values.
	//    (The key is "voice", not "synth": Event already has a method
	//    synth, and ~balance.synth would call it, as with "count" in
	//    04_player_state.scd.)
	if(~balance.voice.notNil) {
		~balance.voice.set(\margin, ~balance.margin, \inside, (~balance.state == 1 or: { ~balance.state == 2 }).asInteger);
	};
}, '/body/balance');

OSCdef(\bodyBalanceState, { |msg|
	~balance.changes = ~balance.changes + 1;
	("balance: " ++ msg[1] ++ "   margin " ++ ~balance.margin.round(0.001)).postln;
}, '/body/balance/state');

"listening on port %".format(NetAddr.langPort).postln;
)


// 2. A tone for the margin. Boot the server first.
(
// margin in meters: inside, the pitch rises as the margin shrinks;
// outside, a beating second voice is added.
SynthDef(\balanceTone, { |out = 0, amp = 0.08, margin = 0.1, inside = 1|
	var closeness, freq, beat, tone, sig;
	// closeness is 0 for a margin of 0.1 m or more, 1 at the edge.
	closeness = (1 - (Lag.kr(margin, 0.05) / 0.1)).clip(0, 1);
	freq = closeness.linexp(0, 1, 220, 660);
	// Q: Why a second oscillator 3 Hz above the first when outside?
	// A: Two close frequencies beat at their difference. The beating is
	//    heard as a tremolo that says "outside" without a new pitch.
	beat = Lag.kr(1 - inside, 0.05);
	tone = SinOsc.ar(freq) + (SinOsc.ar(freq + 3) * beat);
	sig = tone * amp * (0.3 + (0.7 * closeness));
	Out.ar(out, sig ! 2);
}).add;
"balanceTone added".postln;
)


// 3. Start the tone (needs block 2 and the server).
(
~balance.voice = Synth(\balanceTone);
)


// 4. Stop.
(
~balance.voice !? { ~balance.voice.free };
~balance.voice = nil;
OSCdef(\bodyBalance).free;
OSCdef(\bodyBalanceState).free;
)
