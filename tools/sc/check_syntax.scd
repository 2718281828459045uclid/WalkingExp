// check_syntax.scd
// Compiles every code block of the .scd files given on the command line
// without running them. Called by tools/sc_check.sh.
//
// Q: Why not compile the whole file at once?
// A: A lesson file holds several blocks meant to be run one at a time:
//    "( ... )" groups and single lines. Two blocks in a row are not one
//    valid expression, so a whole-file compile reports a syntax error at
//    the second "(" even when every block is correct.
//
// Block rule (the convention of audio/supercollider/*.scd):
//   a line that is "(" opens a block, a line that is ")" closes it;
//   outside blocks, every line that is not empty or a // comment is a
//   block of its own.
// .compile turns code into a Function without running it, or returns nil
// and prints the syntax error. Exit code: number of failed blocks.

(
var failures, blocks, current, inBlock, lines, text;
failures = 0;
thisProcess.argv.do { |path|
	text = File.readAllString(path);
	lines = text.split($\n);
	blocks = List.new;
	inBlock = false;
	current = nil;
	lines.do { |line, i|
		case
		{ inBlock.not and: { line == "(" } } {
			inBlock = true;
			current = [i + 1, List[line]];
		}
		{ inBlock and: { line == ")" } } {
			current[1].add(line);
			blocks.add([current[0], current[1].join("\n")]);
			inBlock = false;
		}
		{ inBlock } { current[1].add(line) }
		{ line.stripWhiteSpace.isEmpty.not and: { line.stripWhiteSpace.beginsWith("//").not } } {
			blocks.add([i + 1, line]);
		};
	};
	if(inBlock) {
		"FAIL  %: block opened at line % is not closed".format(path, current[0]).postln;
		failures = failures + 1;
	};
	blocks.do { |block|
		if(block[1].compile.isNil) {
			"FAIL  %: block at line % does not compile".format(path, block[0]).postln;
			failures = failures + 1;
		};
	};
	"checked %: % blocks".format(path, blocks.size).postln;
};
"sc_check: % failure(s)".format(failures).postln;
failures.exit;
)
