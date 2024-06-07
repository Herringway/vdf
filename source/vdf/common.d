module vdf.common;

import std.range;

struct Mark {
	string name;
	ulong line;
	ulong column;
	void toString(W)(ref W writer) const scope {
		import std.format : formattedWrite;
		writer.formattedWrite!"%s:%s,%s"(name, line, column);
	}
}

class VDFException : Exception {
	Mark start;
	this(Mark mark, string msg, string file = __FILE__, ulong line = __LINE__) @safe pure {
		this.start = mark;
		super(msg, file, line);
	}
	void toString(W)(ref W sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite!"%s@%s(%s): %s (%s)\n%s"(typeid(this).name, file, line, msg, start, info.toString);
	}
    override void toString(scope void delegate(in char[]) sink) const {
        toString!(typeof(sink))(sink);
    }
}
class VDFTokenizationException : VDFException {
	this(Mark mark, string msg, string file = __FILE__, ulong line = __LINE__) @safe pure {
		super(mark, msg, file, line);
	}
}
class VDFParserException : VDFException {
	this(Mark mark, string msg, string file = __FILE__, ulong line = __LINE__) @safe pure {
		super(mark, msg, file, line);
	}
}
class VDFNodeException : VDFException {
	this(Mark mark, string msg, string file = __FILE__, ulong line = __LINE__) @safe pure {
		super(mark, msg, file, line);
	}
}

package enum isPureOutputRange(W) = __traits(compiles, () pure { W w; put(w, 'a'); });
package enum isSafeOutputRange(W) = __traits(compiles, () @safe { W w; put(w, 'a'); });
