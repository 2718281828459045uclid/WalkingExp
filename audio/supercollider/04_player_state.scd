// 04_player_state.scd
// Receives the player state that Godot sends (Lesson 04).
// Sender: game/src/audio/player_state_reporter.gd, through the "Osc"
// autoload (game/src/audio/osc_sender.gd). Message layout:
//   /player/state  x y z speed ground   (Float x4, Integer 0 floor / 1 steep / 2 air)
//   /player/ground name                  (sent on change: floor, steep, air)
// This file uses sclang only. It does not boot the server.
//
// Run block 1, then start game/scenes/lessons/04_osc_bridge.tscn (F6).
// Block 2 prints a summary twice per second. Block 3 stops everything.


// 1. Responders. The latest state goes into ~player.
(
// Q: Why "messages" and not "count" as a key?
// A: An Event is a Collection, and Collection already has a method
//    count. ~player.count would call that method instead of reading
//    the key, and fail.
~player = (
	x: 0, y: 0, z: 0, speed: 0, ground: 2, groundName: \air,
	messages: 0, lastTime: nil, interval: 0
);

OSCdef(\playerState, { |msg, time|
	// msg is an Array: [ '/player/state', x, y, z, speed, ground ]
	~player.x = msg[1];
	~player.y = msg[2];
	~player.z = msg[3];
	~player.speed = msg[4];
	~player.ground = msg[5];
	// time is the arrival time in seconds (sclang's clock); the
	// difference between two arrivals is the send interval plus jitter.
	if(~player.lastTime.notNil) { ~player.interval = time - ~player.lastTime };
	~player.lastTime = time;
	~player.messages = ~player.messages + 1;
}, '/player/state');

OSCdef(\playerGround, { |msg|
	// OSC strings arrive in sclang as Symbols, not Strings.
	~player.groundName = msg[1];
	("ground: " ++ msg[1]).postln;
}, '/player/ground');

"listening on port %".format(NetAddr.langPort).postln;
)


// 2. Print the latest state twice per second.
(
~printer = Routine({
	loop {
		"x % y % z %  speed % m/s  ground %  (% msgs, last interval % ms)".format(
			~player.x.round(0.01),
			~player.y.round(0.01),
			~player.z.round(0.01),
			~player.speed.round(0.01),
			~player.groundName,
			~player.messages,
			(~player.interval * 1000).round(0.1)
		).postln;
		0.5.wait;
	}
}).play;
)


// 3. Stop printing and remove the responders.
(
~printer.stop;
OSCdef(\playerState).free;
OSCdef(\playerGround).free;
)
