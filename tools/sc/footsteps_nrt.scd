// footsteps_nrt.scd
// Offline (non-real-time) render of the footstep SynthDefs of
// audio/supercollider/05_footsteps.scd. Called by tools/footsteps_nrt.sh.
// scsynth renders a score to a file; no real-time server runs and
// nothing plays through the speakers.
//
// Arguments: <path to 05_footsteps.scd> <output .wav path>
// Score: for each surface (grass, dirt, rock), impacts 0.5, 1.5, 3.0 m/s
// and slopes -25, 0, +25 degrees: 27 steps, one every 0.5 s.
// Report: one line per step with peak and RMS (dBFS), and a final line.
// Exit 0 if every step is audible (peak above -60 dBFS), below 0 dBFS,
// and free of NaN and infinity.

(
var args, sourcePath, outPath, text, lines, block, inBlock, score, steps, spacing, options, analyse;
args = thisProcess.argv;
sourcePath = args[0];
outPath = args[1];
spacing = 0.5;

// Q: How is block 1 found?
// A: By the block convention of tools/sc/check_syntax.scd: the first
//    line holding only "(" opens it, the next line holding only ")"
//    closes it. Running it defines the SynthDefs in SynthDescLib.
text = File.readAllString(sourcePath);
lines = text.split($\n);
block = List.new;
inBlock = false;
lines.do { |line|
	if(block.notNil) {
		case
		{ inBlock.not and: { line == "(" } } { inBlock = true }
		{ inBlock and: { line == ")" } } { block.add(nil); inBlock = false; block = block.select(_.notNil).join("\n").interpret; block = nil }
		{ inBlock } { block.add(line) };
	};
};

steps = List.new;
[\stepGrass, \stepDirt, \stepRock].do { |name|
	[0.5, 1.5, 3.0].do { |impact|
		[-25, 0, 25].do { |slope|
			steps.add([name, impact, slope]);
		};
	};
};

score = Score.new;
[\stepGrass, \stepDirt, \stepRock].do { |name|
	score.add([0.0, ['/d_recv', SynthDescLib.global[name].def.asBytes]]);
};
steps.do { |step, i|
	score.add([0.1 + (i * spacing), Synth.basicNew(step[0], Server.default, 1000 + i)
		.newMsg(nil, [amp: 0.4, impact: step[1], slope: step[2]])]);
};
score.add([0.1 + (steps.size * spacing) + 0.5, [\c_set, 0, 0]]);

options = ServerOptions.new.numOutputBusChannels_(2).verbosity_(-1);

analyse = {
	var file, data, frames, failures, peakAll;
	failures = 0;
	peakAll = 0;
	file = SoundFile.openRead(outPath);
	data = FloatArray.newClear(file.numFrames * file.numChannels);
	file.readData(data);
	file.close;
	steps.do { |step, i|
		var start, stop, peak, sumSq, n, bad, x;
		start = ((0.1 + (i * spacing)) * file.sampleRate).asInteger * 2;
		stop = ((0.1 + ((i + 1) * spacing)) * file.sampleRate).asInteger * 2;
		stop = stop.min(data.size);
		peak = 0; sumSq = 0; bad = 0; n = stop - start;
		(start..(stop - 1)).do { |k|
			x = data[k];
			if(x.isNaN or: { x.abs == inf }) { bad = bad + 1 } {
				peak = peak.max(x.abs);
				sumSq = sumSq + (x * x);
			};
		};
		peakAll = peakAll.max(peak);
		"STEP % impact % slope %  peak % dB  rms % dB  bad %".format(
			step[0], step[1], step[2],
			peak.ampdb.round(0.1), (sumSq / n).sqrt.ampdb.round(0.1), bad
		).postln;
		if(peak < -60.dbamp or: { peak >= 1 } or: { bad > 0 }) { failures = failures + 1 };
	};
	"RESULT % steps, % failed, overall peak % dB, file %".format(steps.size, failures, peakAll.ampdb.round(0.1), outPath).postln;
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
