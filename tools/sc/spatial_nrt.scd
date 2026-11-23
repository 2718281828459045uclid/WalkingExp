// spatial_nrt.scd
// Offline (non-real-time) measurement of the spatializer and the
// ambience SynthDefs of audio/supercollider/06_spatial_audio.scd.
// Called by tools/spatial_nrt.sh. scsynth renders a score to a file; no
// real-time server runs and nothing plays through the speakers.
//
// Arguments: <path to 06_spatial_audio.scd> <output .wav path> <speakers>
// Block 1 is run twice, with ~panner = \panAz and \ambisonic. After each
// run, ~spatialize (the function block 1 defines) builds probe SynthDefs
// of white noise. The score then plays, one after another:
//   (each probe case lasts 1 s; the level is measured from 0.2 s on)
//   DIR    probe at 2 m, azimuth -180..180 in 45 degree steps, both panners
//   ELEV   ambisonic probe, azimuth 0, elevation 0, 45, 90 degrees
//   DIST   PanAz probe, azimuth 0, distance 1..128 m: full band, and
//          the part above 4 kHz
//   SOURCE \crickets, \bird, \windBed (strength 0.3 and 1.0)
// Report: RMS per channel in dBFS for each probe case; peak, RMS, NaN
// count for each source. Exit 0 if every source is audible (peak above
// -60 dBFS), below 0 dBFS, and free of NaN and infinity.

(
var args, sourcePath, outPath, speakers, runBlock, cases, score, t, options, analyse, makeProbes;
args = thisProcess.argv;
sourcePath = args[0];
outPath = args[1];
speakers = (args[2] ? "2").asInteger;

// Runs block 1 of the file (the first lines "(" ... ")").
runBlock = {
	var lines, block, inBlock, done;
	lines = File.readAllString(sourcePath).split($\n);
	block = List.new;
	inBlock = false;
	done = false;
	lines.do { |line|
		if(done.not) {
			case
			{ inBlock.not and: { line == "(" } } { inBlock = true }
			{ inBlock and: { line == ")" } } { done = true }
			{ inBlock } { block.add(line) };
		};
	};
	block.join("\n").interpret;
};

// Probe SynthDefs built with the spatializer of the last block run.
// \probe<suffix> is white noise; \probeHigh<suffix> keeps only the
// output above 4 kHz, to see the air absorption.
makeProbes = { |suffix|
	var spatialize;
	spatialize = ~spatialize;
	SynthDef(("probe" ++ suffix).asSymbol, { |az = 0, el = 0, dist = 2|
		Out.ar(0, spatialize.(WhiteNoise.ar * 0.3, az, el, dist, 2, 25, 0.15));
	}).add;
	SynthDef(("probeHigh" ++ suffix).asSymbol, { |az = 0, el = 0, dist = 2|
		var sig;
		sig = spatialize.(WhiteNoise.ar * 0.3, az, el, dist, 2, 25, 0.15);
		Out.ar(0, sig.collect { |c| HPF.ar(HPF.ar(c, 4000), 4000) });
	}).add;
};

~speakers = speakers;
~panner = \ambisonic;
runBlock.value;
makeProbes.("B");
~panner = \panAz;
runBlock.value;
makeProbes.("Az");

// cases: [label, synth name, arguments, start, length, measure from, kind]
cases = List.new;
t = 0.1;
[\Az, \B].do { |p|
	(-180, -135 .. 180).do { |deg|
		cases.add(["DIR % az %".format(p, deg), ("probe" ++ p).asSymbol, [az: deg.degrad], t, 1, 0.2, \probe]);
		t = t + 1;
	};
};
[0, 45, 90].do { |deg|
	cases.add(["ELEV B el %".format(deg), \probeB, [el: deg.degrad], t, 1, 0.2, \probe]);
	t = t + 1;
};
[1, 2, 4, 8, 16, 32, 64, 128].do { |d|
	cases.add(["DIST full dist %".format(d), \probeAz, [dist: d], t, 1, 0.2, \probe]);
	t = t + 1;
	cases.add(["DIST high dist %".format(d), \probeHighAz, [dist: d], t, 1, 0.2, \probe]);
	t = t + 1;
};
cases.add(["SOURCE crickets", \crickets, [dist: 2], t, 6, 2.5, \source]);
t = t + 6;
cases.add(["SOURCE bird", \bird, [dist: 2], t, 12, 2.5, \source]);
t = t + 12;
cases.add(["SOURCE windBed 0.3", \windBed, [strength: 0.3], t, 8, 4, \source]);
t = t + 8;
cases.add(["SOURCE windBed 1.0", \windBed, [strength: 1.0], t, 8, 4, \source]);
t = t + 8;

score = Score.new;
[\probeAz, \probeHighAz, \probeB, \probeHighB, \crickets, \bird, \windBed].do { |name|
	score.add([0.0, ['/d_recv', SynthDescLib.global[name].def.asBytes]]);
};
cases.do { |c, i|
	score.add([c[3], Synth.basicNew(c[1], Server.default, 1000 + i).newMsg(nil, c[2])]);
	// n_free cuts the synth at the end of its segment, release or not.
	score.add([c[3] + c[4] - 0.001, ['/n_free', 1000 + i]]);
};
score.add([t + 0.1, [\c_set, 0, 0]]);

options = ServerOptions.new.numOutputBusChannels_(speakers).verbosity_(-1);

analyse = {
	var file, data, sr, failures;
	failures = 0;
	file = SoundFile.openRead(outPath);
	sr = file.sampleRate;
	data = FloatArray.newClear(file.numFrames * speakers);
	file.readData(data);
	file.close;
	cases.do { |c|
		var start, stop, sumSq, peak, bad, x, rms, total;
		start = ((c[3] + c[5]) * sr).asInteger;
		stop = ((c[3] + c[4] - 0.01) * sr).asInteger;
		sumSq = 0 ! speakers;
		peak = 0;
		bad = 0;
		(start..(stop - 1)).do { |frame|
			speakers.do { |ch|
				x = data[(frame * speakers) + ch];
				if(x.isNaN or: { x.abs == inf }) { bad = bad + 1 } {
					sumSq[ch] = sumSq[ch] + (x * x);
					peak = peak.max(x.abs);
				};
			};
		};
		rms = sumSq.collect { |v| (v / (stop - start)).sqrt };
		// Total power of all channels, as one level.
		total = (rms.squared.sum).sqrt;
		if(c[6] == \probe) {
			"% : channels % dB  total % dB".format(
				c[0], rms.collect { |r| r.ampdb.round(0.1) }, total.ampdb.round(0.1)
			).postln;
		} {
			"% : peak % dB  rms % dB  bad %".format(
				c[0], peak.ampdb.round(0.1), total.ampdb.round(0.1), bad
			).postln;
			if(peak < -60.dbamp or: { peak >= 1 } or: { bad > 0 }) { failures = failures + 1 };
		};
	};
	"RESULT % channels, % sources failed, file %".format(speakers, failures, outPath).postln;
	AppClock.sched(0, { failures.exit; nil });
};

score.recordNRT(
	outputFilePath: outPath,
	sampleRate: 48000,
	headerFormat: "WAV",
	sampleFormat: "float",
	options: options,
	action: analyse
);
)
