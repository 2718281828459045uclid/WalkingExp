// footstep_timing_listener.scd
// Receiving half of tools/footstep_timing.sh. Run by sclang in batch mode;
// the sending half is tools/godot/walk_steps.gd, run by Godot.
//
// Records, for every /foot/step, the arrival time and the time the step
// should sound: the bundle's time tag, or the arrival time for a plain
// message. When no step has arrived for 1.5 s, it prints statistics and
// exits 0 (1 if fewer than 5 steps arrived). It does not boot the server.
//
// Both times are in sclang's clock (seconds since sclang started). For a
// bundle, OSCdef passes the time tag, already converted to that clock, as
// the "time" argument; thisThread.seconds is the arrival time.

(
var arrivals, tags, lastArrival, report, stats, intervals;
arrivals = List.new;
tags = List.new;

// Mean, standard deviation, minimum and maximum of a collection, in ms.
stats = { |values|
	var mean, sd;
	mean = values.mean;
	sd = (values.collect { |v| (v - mean).squared }.mean).sqrt;
	"mean % ms  sd % ms  min % ms  max % ms".format(
		(mean * 1000).round(0.01), (sd * 1000).round(0.01),
		(values.minItem * 1000).round(0.01), (values.maxItem * 1000).round(0.01)
	)
};

intervals = { |times| times.differentiate.drop(1) };

report = {
	var a, t, margins;
	a = arrivals.array;
	t = tags.array;
	"STEPS %".format(a.size).postln;
	if(a.size >= 5) {
		// Q: Why compare intervals rather than absolute times?
		// A: The listener cannot know when Godot detected a step. It can
		//    measure how evenly the steps are spaced: that is what the
		//    ear hears as rhythm.
		("ARRIVAL intervals  " ++ stats.(intervals.(a))).postln;
		("TAG     intervals  " ++ stats.(intervals.(t))).postln;
		// The tag intervals are the rhythm of the simulation; the arrival
		// intervals add the transport and frame timing on top. Their
		// difference is the jitter a receiver adds by playing on arrival.
		("JITTER  arrival - tag interval  " ++ stats.(intervals.(a) - intervals.(t))).postln;
		// margin = tag - arrival: how early the step arrived. Negative
		// margins are late steps.
		margins = t - a;
		("MARGIN  tag - arrival  " ++ stats.(margins)).postln;
		"LATE %".format(margins.count { |m| m < 0 }).postln;
	};
	AppClock.sched(0, { (if(a.size >= 5) { 0 } { 1 }).exit; nil });
};

OSCdef(\footTiming, { |msg, time|
	var arrival;
	arrival = thisThread.seconds;
	// Landings (foot 2) are not part of the walking rhythm.
	if(msg[1] != 2) {
		arrivals.add(arrival);
		tags.add(time);
		lastArrival = arrival;
	};
}, '/foot/step');

"PORT %".format(NetAddr.langPort).postln;

// Check twice per second whether the walk has ended.
AppClock.sched(0.5, {
	var now;
	now = Main.elapsedTime;
	if(lastArrival.notNil and: { now - lastArrival > 1.5 }) {
		report.value; nil
	} {
		if(now > 40) { "TIMEOUT".postln; report.value; nil } { 0.5 }
	}
});
)
