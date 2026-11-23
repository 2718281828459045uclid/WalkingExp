// 05_footsteps.scd
// Synthesized footsteps, played at the time Godot stamps on them (Lesson 05).
// Sender: game/src/audio/footstep_reporter.gd, through the "Osc"
// autoload (game/src/audio/osc_sender.gd, send_bundle). Message layout:
//   /foot/step  foot impact slope grass dirt rock
//     foot    Integer: 0 left, 1 right, 2 both (landing)
//     impact  Float, m/s: walking speed, or falling speed for a landing
//     slope   Float, degrees along the walk: + uphill, - downhill
//     grass dirt rock   Float weights, sum 1
// In time-tagged mode each message arrives inside a bundle whose time tag
// says when the step should sound.
//
// Block 1 defines the SynthDefs; it needs no server and is also read by
// tools/footsteps_nrt.sh for the offline render. Blocks 2-4 need the
// server: boot it yourself (s.boot) before block 2.
// Block 2: responder. Block 3: timing report. Block 4: stop.


// 1. SynthDefs: one per surface, sharing one heel-and-ball envelope.
(
var footEnvelopes;

// Q: What shape does one footstep have?
// A: Two contacts (Farnell, "Designing Sound", footsteps chapter): the
//    heel strikes, the foot rolls, the ball of the foot lands. Faster
//    walking shortens the roll. Downhill the heel lands harder; uphill
//    the ball pushes harder.
// Returns [heel, ball], two audio-rate envelopes. slope in degrees.
footEnvelopes = { |impact, slope|
	var roll, heelLevel, ballLevel, heel, ball;
	roll = (0.10 - (impact * 0.015)).clip(0.04, 0.10);
	heelLevel = (1 - (slope / 40)).clip(0.4, 1.6);
	ballLevel = (1 + (slope / 40)).clip(0.4, 1.6);
	heel = EnvGen.ar(Env.perc(0.002, 0.07, 1, -4)) * heelLevel;
	ball = EnvGen.ar(Env([0, 0, 1, 0], [roll, 0.004, 0.09], [0, 0, -4])) * ballLevel;
	[heel, ball]
};

// Grass: many small blade snaps (dense filtered clicks) and a soft swish.
SynthDef(\stepGrass, { |out = 0, amp = 0.3, impact = 1.5, slope = 0, pan = 0|
	var heel, ball, env, snaps, swish, sig;
	# heel, ball = footEnvelopes.(impact, slope);
	env = heel + ball;
	// Q: Why Dust2 into a band-pass filter?
	// A: Dust2 makes single-sample clicks at random times. The filter
	//    rings briefly at each click, which turns a click into a tiny
	//    snap with a pitch region. More impact, more snaps.
	snaps = BPF.ar(Dust2.ar(900 + (impact * 500)), 3800, 0.9) * 5;
	swish = HPF.ar(PinkNoise.ar, 1800) * 0.25;
	sig = (snaps + swish) * env;
	sig = sig * amp * impact.linlin(0, 4, 0.3, 1.2);
	Line.kr(0, 0, 0.4, doneAction: Done.freeSelf);
	Out.ar(out, Pan2.ar(sig, pan));
}).add;

// Dirt: a low thump of the body weight, plus sparse grit.
SynthDef(\stepDirt, { |out = 0, amp = 0.3, impact = 1.5, slope = 0, pan = 0|
	var heel, ball, env, thump, grit, sig;
	# heel, ball = footEnvelopes.(impact, slope);
	env = heel + ball;
	// The cutoff rises with impact: a harder step has more high energy.
	thump = LPF.ar(WhiteNoise.ar, 250 + (impact * 150)) * env * 3;
	grit = HPF.ar(Dust2.ar(250 + (impact * 150)), 1500) * env * 2;
	sig = thump + grit + (BPF.ar(WhiteNoise.ar, 900, 1.2) * env * 0.4);
	sig = sig * amp * impact.linlin(0, 4, 0.3, 1.2);
	Line.kr(0, 0, 0.4, doneAction: Done.freeSelf);
	Out.ar(out, Pan2.ar(sig, pan));
}).add;

// Rock: a struck solid. Modal synthesis (van den Doel, Kry, Pai,
// "FoleyAutomatic", 2001): a short excitation drives a bank of
// resonators, one per vibration mode of the object.
SynthDef(\stepRock, { |out = 0, amp = 0.3, impact = 1.5, slope = 0, pan = 0|
	var heel, ball, env, exciter, modes, scuff, sig;
	# heel, ball = footEnvelopes.(impact, slope);
	env = heel + ball;
	// Q: Why noise as the exciter?
	// A: Noise has energy at every frequency, so it sets every mode
	//    ringing; the modes then carry the pitch. The envelope gives the
	//    noise the shape of the heel and ball contacts.
	exciter = WhiteNoise.ar * env;
	// Klank: [frequencies, amplitudes, decay times in seconds]. The
	// ratios are inharmonic, as for an irregular stone, not a string.
	// freqscale lowers the pitch on soft (slow) steps a little.
	modes = Klank.ar(`[
		[620, 1470, 2430, 3510, 5230],
		[1, 0.6, 0.45, 0.3, 0.2],
		[0.06, 0.045, 0.035, 0.025, 0.018]
	], exciter, impact.linlin(0, 4, 0.9, 1.1)) * 0.08;
	scuff = BPF.ar(WhiteNoise.ar, 2500, 1.5) * env * 0.3;
	sig = modes + scuff;
	sig = sig * amp * impact.linlin(0, 4, 0.3, 1.2);
	Line.kr(0, 0, 0.4, doneAction: Done.freeSelf);
	Out.ar(out, Pan2.ar(sig, pan));
}).add;

"footstep SynthDefs added".postln;
)


// 2. Responder: play each step at its time tag. Boot the server first.
(
// Q: What is "time" in the responder function?
// A: For a bundle, the time tag converted to sclang's clock (seconds
//    since sclang started, like thisThread.seconds). For a plain message,
//    about the arrival time. time - thisThread.seconds is how far in the
//    future the step should sound.
~steps = (count: 0, late: 0, margins: List.new, amp: 0.4);
~stepNames = [\stepGrass, \stepDirt, \stepRock];

OSCdef(\footStep, { |msg, time|
	var foot, impact, slope, weights, delta;
	foot = msg[1];
	impact = msg[2];
	slope = msg[3];
	weights = msg[4..6];
	delta = time - thisThread.seconds;
	// The OSC tag "immediately" reaches sclang as a meaningless large
	// time; treat any delta above one second as "now".
	if(delta > 1) { delta = 0 };
	~steps.count = ~steps.count + 1;
	~steps.margins.add(delta);
	if(delta < 0) { ~steps.late = ~steps.late + 1 };
	// Q: What does makeBundle do with delta?
	// A: It collects the messages the function sends to the server and
	//    sends them as one bundle tagged "now + delta". The server starts
	//    the synths at that time, sample-accurate. A late step (delta < 0)
	//    is played at once instead.
	s.makeBundle(delta.max(0), {
		weights.do { |w, i|
			if(w > 0.02) {
				Synth(~stepNames[i], [
					amp: w * ~steps.amp,
					impact: impact,
					slope: slope,
					pan: [-0.15, 0.15, 0][foot]
				]);
			};
		};
	});
}, '/foot/step');

"listening for /foot/step on port %".format(NetAddr.langPort).postln;
)


// 3. Timing report: steps received, late steps, margin range in ms.
(
var m;
m = ~steps.margins.array;
if(m.isEmpty) { "no steps yet".postln } {
	"steps % late %  margin min % ms  mean % ms  max % ms".format(
		~steps.count, ~steps.late,
		(m.minItem * 1000).round(0.1), (m.mean * 1000).round(0.1), (m.maxItem * 1000).round(0.1)
	).postln;
};
)


// 4. Stop: remove the responder.
(
OSCdef(\footStep).free;
)
