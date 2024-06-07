import std.algorithm.comparison;
import std.file;
import std.stdio;

import vdf.parser;

int main(string[] args) {
	File output = stdout;
	if (args.length < 2) {
		writeln("vdf_reparse file [output]");
		return 1;
	} else if (args.length > 2) {
		output = File(args[2], "w");
	}
	auto doc = read(args[1]);
	if ((doc.length >= 4) && (cast(uint[])(doc[0 .. uint.sizeof]))[0].among(0x06565527, 0x06565528, 0x07564427, 0x07564428)) {
		stderr.writeln("Cannot read binary VDF!");
		return 1;
	}
	output.writeln(parseVDF(cast(char[])doc));
		return 0;
}
