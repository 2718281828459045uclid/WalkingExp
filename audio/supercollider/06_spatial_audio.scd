// 06_spatial_audio.scd
// Positioned ambience sources and a wind bed, placed around the listener
// from coordinates Godot computes (Lesson 06).
// Sender: game/src/audio/spatial_audio_reporter.gd, through the "Osc"
// autoload (game/src/audio/osc_sender.gd, send_bundle). Messages:
//   /emitter/kind  id kind amp        once per second per emitter
//   /emitter/pos   id az el dist      30 times per second per emitter
//   /wind          strength az        30 times per second
//     az, el   radians. az 0 = ahead, +PI/2 = right, unwrapped by Godot,
//              so it changes by less than PI between messages.
//              el 0 = horizontal, +PI/2 = straight up.
//     dist     meters.  strength 0..1.
// kind names a SynthDef of block 1 (\crickets, \bird, \noiseProbe).
//
// Block 1 defines the SynthDefs; it needs no server and is also read by
// tools/spatial_nrt.sh for the offline render. Set ~speakers (number of
// output channels, default 2) and ~panner (\panAz or \ambisonic, default
// \panAz) before running it. Blocks 2-4 need the server: boot it
// yourself (s.boot) before block 2. Block 2: responders. Block 3:
// report. Block 4: stop.
// The footsteps of 05_footsteps.scd run beside this file unchanged.


// 1. SynthDefs: a shared spatializer and three sources; the wind bed.
(
var speakers, panner, spatialize;
speakers = ~speakers ? 2;
panner = ~panner ? \panAz;

// Q: What does every positioned source need, whatever its sound?
// A: Four steps, in this order:
//    1. Smooth the control values. They arrive 30 times per second, in
//       steps; Lag turns each step into an exponential glide.
//    2. Distance attenuation. A point source spreads its power over a
//       sphere of area 4 pi d^2, so the amplitude falls as 1/d: -6 dB
//       per doubling of distance. Inside refDist the gain stays at 1,
//       so a source at the listener does not become infinitely loud.
//    3. Air absorption. Air absorbs high frequencies more than low ones,
//       and the loss grows with distance. Here a low-pass filter whose
//       cutoff falls as the distance grows stands in for it.
//    4. Panning: from the direction to a gain per loudspeaker.
// Returns an array of `speakers` audio channels.
spatialize = { |sig, az, el, dist, refDist, airMeters, lagTime|
	var smoothAz, smoothEl, smoothDist, gain, cutoff, w, x, y, z;
	smoothAz = Lag.kr(az, lagTime);
	smoothEl = Lag.kr(el, lagTime);
	smoothDist = Lag.kr(dist, lagTime);
	gain = refDist / smoothDist.max(refDist);
	// At dist = airMeters the cutoff is 10 kHz; at 4 * airMeters, 4 kHz.
	cutoff = (20000 / (1 + (smoothDist / airMeters))).clip(200, 20000);
	sig = LPF.ar(sig, cutoff) * gain;
	// Q: Why is the choice of panner an sclang `if`, not a UGen?
	// A: It runs once, while the SynthDef is built. The SynthDef that
	//    goes to the server contains only one of the two panners.
	if(panner == \ambisonic) {
		// Q: What are W, X, Y, Z?
		// A: First-order Ambisonics (B-format). The sound field at one
		//    point is described by four signals: W, the pressure (an
		//    omnidirectional microphone), and X, Y, Z, the pressure
		//    gradient along three axes (three figure-eight microphones).
		//    A source in direction (az, el) is encoded as
		//      W = s / sqrt(2)   X = s cos(az) cos(el)
		//      Y = s sin(az) cos(el)   Z = s sin(el)   (up to sign).
		//    The decoder then forms, for each loudspeaker, a virtual
		//    microphone pointing at it. PanB takes the azimuth in units
		//    of PI and the elevation in units of PI/2 (measured: el 1 is
		//    straight up). DecodeB2 decodes to a horizontal ring and
		//    ignores Z.
		# w, x, y, z = PanB.ar(sig, smoothAz / pi, smoothEl / (pi / 2));
		DecodeB2.ar(speakers, w, x, y)
	} {
		// PanAz: equal-power panning between the two neighboring
		// loudspeakers of a ring. Its position is periodic with period 2,
		// so position = az / PI puts az = PI and az = -PI in one place.
		// PanAz ignores the elevation.
		PanAz.ar(speakers, sig, smoothAz / pi)
	}
};
~spatialize = spatialize;

// Crickets: three insects, each a tone switched by two pulse trains.
SynthDef(\crickets, { |out = 0, amp = 0.3, az = 0, el = 0, dist = 10,
	refDist = 2, airMeters = 25, lagTime = 0.15, gate = 1|
	var env, voices, sig;
	env = EnvGen.kr(Env.asr(2, 1, 2), gate, doneAction: Done.freeSelf);
	voices = 3.collect {
		var tone, strokes, groups;
		tone = SinOsc.ar(Rand(4200, 4800));
		// Q: Why two pulse trains?
		// A: A cricket's chirp is a group of wing strokes. The fast
		//    train (about 30 Hz) is the strokes; the slow one (about
		//    2 Hz) opens a group of strokes and pauses. Rand gives each
		//    insect its own rates when the synth starts.
		strokes = Lag.ar(LFPulse.ar(Rand(28, 34), 0, 0.4), 0.002);
		groups = Lag.kr(LFPulse.kr(Rand(1.6, 2.4), Rand(0, 1), 0.3), 0.01);
		tone * strokes * groups
	};
	sig = Mix(voices) * 0.2 * amp * env;
	Out.ar(out, spatialize.(sig, az, el, dist, refDist, airMeters, lagTime));
}).add;

// Bird: short falling-rising whistles at random times.
SynthDef(\bird, { |out = 0, amp = 0.3, az = 0, el = 0, dist = 10,
	refDist = 2, airMeters = 25, lagTime = 0.15, gate = 1|
	var env, trig, pitch, freq, level, sig;
	env = EnvGen.kr(Env.asr(2, 1, 2), gate, doneAction: Done.freeSelf);
	trig = Dust.kr(0.7);
	pitch = TRand.kr(0.85, 1.15, trig);
	freq = EnvGen.kr(Env([3000, 4200, 2800], [0.05, 0.08], \exp), trig) * pitch;
	level = EnvGen.kr(Env.perc(0.01, 0.12), trig);
	// A 25 Hz amplitude wobble makes the whistle a trill.
	sig = SinOsc.ar(freq) * level * SinOsc.kr(25).range(0.5, 1);
	sig = sig * 0.3 * amp * env;
	Out.ar(out, spatialize.(sig, az, el, dist, refDist, airMeters, lagTime));
}).add;

// Pink noise: a steady source for listening tests and measurements.
SynthDef(\noiseProbe, { |out = 0, amp = 0.3, az = 0, el = 0, dist = 10,
	refDist = 2, airMeters = 25, lagTime = 0.15, gate = 1|
	var env, sig;
	env = EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: Done.freeSelf);
	sig = PinkNoise.ar * amp * env;
	Out.ar(out, spatialize.(sig, az, el, dist, refDist, airMeters, lagTime));
}).add;

// Wind: a bed that surrounds the listener, plus one whistling component
// that comes from the wind's direction.
SynthDef(\windBed, { |out = 0, amp = 0.3, strength = 0.3, az = 0, lagTime = 1, gate = 1|
	var env, s, gust, diffuse, direct, sig;
	env = EnvGen.kr(Env.asr(3, 1, 3), gate, doneAction: Done.freeSelf);
	s = Lag.kr(strength, lagTime);
	// Slow swells (one every few seconds) times a faster flutter.
	gust = LFNoise2.kr(0.15).range(0.5, 1.0) * LFNoise2.kr(0.9).range(0.8, 1.0);
	// Q: Why one noise generator per loudspeaker?
	// A: The same noise in every channel sounds like one source between
	//    the speakers. Independent noise in each channel (decorrelated)
	//    has no position: it sounds like air all around.
	diffuse = speakers.collect {
		BPF.ar(PinkNoise.ar, LFNoise2.kr(0.2).range(300, 700) * (0.6 + s), 0.8)
	};
	// A resonant low-pass sweeps with the gusts: the whistle of wind past
	// an edge. It rises in pitch as the wind grows.
	direct = RLPF.ar(WhiteNoise.ar, 400 + (gust * s * 1400), 0.15) * 0.15;
	direct = PanAz.ar(speakers, direct, Lag.kr(az, 0.3) / pi);
	sig = (diffuse * 0.8) + direct;
	// Q: Why strength squared?
	// A: Strength is a control from 0 to 1, not an amplitude. Squared,
	//    the low half of the range stays quiet and the top grows fast,
	//    closer to how wind noise grows with wind speed.
	sig = sig * gust * s.squared * amp * 2 * env;
	Out.ar(out, sig);
}).add;

"spatial SynthDefs added: % channels, %".format(speakers, panner).postln;
)


// 2. Responders: one synth per emitter, one wind bed. Boot the server first.
(
// ~emitters: id -> (kind: Symbol, amp: Float, node: Synth or nil, seen: seconds)
// The key is "node", not "synth": Event already has a method `synth`.
~emitters = ~emitters ? Dictionary.new;

OSCdef(\emitterKind, { |msg|
	var id, kind, amp, e;
	id = msg[1];
	kind = msg[2];
	amp = msg[3];
	e = ~emitters[id];
	if(e.isNil) {
		~emitters[id] = (kind: kind, amp: amp, node: nil, seen: thisThread.seconds);
	} {
		// The scene may change an emitter's kind while running.
		if(e.kind != kind) {
			e.node !? { e.node.release };
			e.node = nil;
			e.kind = kind;
		};
		e.amp = amp;
		e.node !? { e.node.set(\amp, amp) };
	};
}, '/emitter/kind');

OSCdef(\emitterPos, { |msg|
	var id, e;
	id = msg[1];
	e = ~emitters[id];
	// Q: What if a position arrives before the emitter's kind?
	// A: It is ignored. The kind arrives within one announce interval
	//    (1 s), and the next position after it starts the synth.
	if(e.notNil) {
		// Q: Why start the synth here and not when the kind arrives?
		// A: Lag starts from the first value it receives. A synth
		//    started with az 0 and dist 10 would glide from there to the
		//    true position. Started with the true position, it glides
		//    from nowhere.
		if(e.node.isNil) {
			e.node = Synth(e.kind, [amp: e.amp, az: msg[2], el: msg[3], dist: msg[4]]);
		} {
			e.node.set(\az, msg[2], \el, msg[3], \dist, msg[4]);
		};
		e.seen = thisThread.seconds;
	};
}, '/emitter/pos');

OSCdef(\wind, { |msg|
	if(~wind.isNil) {
		~wind = Synth(\windBed, [strength: msg[1], az: msg[2]]);
	} {
		~wind.set(\strength, msg[1], \az, msg[2]);
	};
}, '/wind');

"listening for /emitter/kind, /emitter/pos, /wind on port %".format(NetAddr.langPort).postln;
)


// 3. Report: each emitter's kind and when it was last positioned.
(
var now;
now = thisThread.seconds;
if(~emitters.isNil or: { ~emitters.isEmpty }) { "no emitters yet".postln } {
	~emitters.keys.asArray.sort.do { |id|
		var e;
		e = ~emitters[id];
		"emitter %  % amp %  synth %  last position % s ago".format(
			id, e.kind, e.amp.round(0.01), e.node.notNil, (now - e.seen).round(0.01)
		).postln;
	};
};
"wind bed running: %".format(~wind.notNil).postln;
)


// 4. Stop: release the synths and remove the responders.
(
OSCdef(\emitterKind).free;
OSCdef(\emitterPos).free;
OSCdef(\wind).free;
~emitters !? { ~emitters.do { |e| e.node !? { e.node.release } } };
~emitters = nil;
~wind !? { ~wind.release };
~wind = nil;
)
