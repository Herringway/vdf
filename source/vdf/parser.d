module vdf.parser;

import std.algorithm.comparison;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.exception;
import std.format;
import std.range;
import std.sumtype;
import std.typecons;

import vdf.common;
import vdf.tokenizer;

struct Node {
	private alias Payload = SumType!(const(char)[], Node[]);
	private Payload payload;
	private size_t iterationIndex;
	const(char)[] key;
	const(char)[] conditional;
	Mark start;
	this(const char[] key, Node[] nodes, const char[] conditional = "") @safe pure {
		this.key = key;
		this.conditional = conditional;
		setValue(Payload(nodes));
	}
	this(const char[] key, const char[] str, const char[] conditional = "") @safe pure {
		this.key = key;
		this.conditional = conditional;
		setValue(Payload(str));
	}
	alias str = get!(const(char)[]);
	alias array = get!(Node[]);
	const(char)[] get(T: const(char)[])() const {
		return payload.match!(
			(const(char)[] v) => v,
			(const(Node)[] v) => assert(0),
		);
	}
	inout(Node[]) get(T: Node[])() inout {
		return payload.match!(
			(const(char)[] v) => assert(0),
			(inout(Node)[] v) => v,
		);
	}
	ref inout(Node) opIndex(string key) inout @safe pure {
		if (auto found = key in this) {
			return *found;
		}
		throw new VDFNodeException(start, "Key " ~ key ~ " not found");
	}
	bool opEquals(const char[] comparison) const @safe pure => str == comparison;
	bool opEquals(const Node comparison) const @safe pure {
		return (this.key == comparison.key) &&
			(this.conditional == comparison.conditional) &&
			(this.payload == comparison.payload);
	}
	size_t length() const @safe pure => array.length;
	inout(Node)* opBinaryRight(string op : "in")(string key) inout {
		foreach (idx, node; array) {
			if (node.key == key) {
				return &array[idx];
			}
		}
		return null;
	}
	ref inout(Node) opIndex(size_t index) inout @safe pure {
		return array[index];
	}
	void opAssign()(auto ref Node node) {
		setValue(node.payload);
		this.key = node.key;
		this.conditional = node.conditional;
		this.start = node.start;
	}
	void opOpAssign(string op: "~")(Node node) {
		payload.match!(
			(const(char)[] v) => assert(0),
			(ref Node[] v) => v ~= node,
		);
	}
	private void setValue(Payload payload) @trusted pure {
		this.payload = payload;
	}
	// this is an abomination... can't infer attributes automatically because of mutual recursion
	enum toStringBody = q{
		void indent() {
			foreach (i; 0 .. indentLevel) {
				put(writer, "\t");
			}
		}
		indent();
		writer.formattedWrite!`"%s"`(escape(key));
		payload.match!(
			(const(char)[] v) {
				writer.formattedWrite!`	"%s"`(escape(v));
				if (conditional != "") {
					writer.formattedWrite!`	[%s]`(conditional);
				}
				put(writer, "\n");
			},
			(const Node[] nodes) {
				if (conditional != "") {
					writer.formattedWrite!"	[%s]"(conditional);
				}
				put(writer, "	{\n");
				foreach (node; nodes) {
					node.toString!W(writer, indentLevel + 1);
				}
				indent();
				put(writer, "}\n");
			},
		);
	};
	void toString(W)(W writer, size_t indentLevel = 0) const if (!isPureOutputRange!W && !isSafeOutputRange!W) {
		mixin(toStringBody);
	}
	void toString(W)(W writer, size_t indentLevel = 0) const pure if (isPureOutputRange!W && !isSafeOutputRange!W) {
		mixin(toStringBody);
	}
	void toString(W)(W writer, size_t indentLevel = 0) const @safe if (!isPureOutputRange!W && isSafeOutputRange!W) {
		mixin(toStringBody);
	}
	void toString(W)(W writer, size_t indentLevel = 0) const @safe pure if (isPureOutputRange!W && isSafeOutputRange!W) {
		mixin(toStringBody);
	}
	inout(Node) save() inout @safe pure {
		return this;
	}
	auto front() inout @safe pure {
		return tuple!("key", "node")(cast(const(char)[])array[iterationIndex].key, cast()array[iterationIndex]);
	}
	void popFront() @safe pure {
		iterationIndex++;
	}
	bool empty() const @safe pure {
		return iterationIndex >= length;
	}
}
private const(char)[] unescape(scope const(char)[] input) @safe pure {
	const(char)[] output;
	output.reserve(input.length);
	foreach (ref idx, chr; input) {
		if (chr == '\\') {
			idx++;
			enforce (idx < input.length, new Exception("End of input reached while looking for escape character"));
			switch (input[idx]) {
				case '"':
					output ~= "\"";
					break;
				case 't':
					output ~= "\t";
					break;
				case 'n':
					output ~= "\n";
					break;
				case '\\':
					output ~= "\\";
					break;
				default: throw new Exception("Illegal escape character :\\" ~ input[idx]);
			}
		} else {
			output ~= chr;
		}
	}
	return output;
}

@safe pure unittest {
	assert(unescape("hello") == "hello");
	assert(unescape(`he\"llo`) == `he"llo`);
	assert(unescape(`\thello`) == "\thello");
	assert(unescape(`\nhello`) == "\nhello");
	assert(unescape(`\\hello`) == "\\hello");
	assertThrown(unescape("hello\\"));
	assertThrown(unescape("hello\\q"));
}
private const(char)[] escape(scope const(char)[] input) @safe pure {
	const(char)[] output;
	output.reserve(input.length);
	foreach (ref idx, chr; input) {
		switch (chr) {
			case '\\': output ~= `\\`; break;
			case '\t': output ~= `\t`; break;
			case '\n': output ~= `\n`; break;
			case '"': output ~= `\"`; break;
			default: output ~= chr; break;
		}
	}
	return output;
}

@safe pure unittest {
	assert(escape("hello") == "hello");
	assert(escape(`he"llo`) == `he\"llo`);
	assert(escape("\thello") == `\thello`);
	assert(escape("\nhello") == `\nhello`);
	assert(escape("\\hello") == `\\hello`);
}

private Node parseNode(ref Tokenizer tokens) @safe pure {
	void nextToken() {
		tokens.popFront();
		tokens.skipOver!(x => x.type == Token.Type.comment)();
	}
	enforce(tokens.front.type == Token.Type.scalar, new VDFParserException(tokens.front.start, "Expecting a key"));
	Node result;
	assert(tokens.front.text[0] == '"', "Missing quotation marks");
	assert(tokens.front.text[$ - 1] == '"', "Missing quotation marks");
	result.key = unescape(tokens.front.text[1 .. $ - 1]);
	result.start = tokens.front.start;
	nextToken();
	enforce(!tokens.empty || (tokens.front.type == Token.Type.endOfDocument), new VDFParserException(tokens.front.start, "Unexpected end of document"));
	if (tokens.front.type == Token.Type.braceLeft) {
		nextToken();
		enforce((tokens.front.type == Token.Type.scalar), new VDFParserException(tokens.front.start, "Unexpected token"));
		result.conditional = tokens.front.text;
		nextToken();
		enforce((tokens.front.type == Token.Type.braceRight), new VDFParserException(tokens.front.start, "Expecting a ']'"));
		nextToken();
	}
	if (tokens.front.type == Token.Type.curlyLeft) {
		nextToken();
		result.setValue(Node.Payload((Node[]).init));
		while (!tokens.front.type.among!(Token.Type.curlyRight, Token.Type.endOfDocument)) {
			result ~= parseNode(tokens);
		}
		nextToken();
	} else if (tokens.front.type == Token.Type.scalar) {
		result.setValue(Node.Payload(unescape(tokens.front.text[1 .. $ - 1])));
		nextToken();
	} else {
		throw new VDFParserException(tokens.front.start, "Unexpected token");
	}
	if (tokens.front.type == Token.Type.braceLeft) {
		nextToken();
		enforce((tokens.front.type == Token.Type.scalar), new VDFParserException(tokens.front.start, "Unexpected token"));
		result.conditional = tokens.front.text;
		nextToken();
		enforce((tokens.front.type == Token.Type.braceRight), new VDFParserException(tokens.front.start, "Expecting a ']'"));
		nextToken();
	}
	return result;
}

Node parseVDF(const char[] data) @safe pure {
	auto tokens = Tokenizer(data);
	return parseNode(tokens);
}

@safe pure unittest {
	import std.conv : text;
	void roundTripNode(Node node) {
		assert(parseVDF(node.text) == node);
	}
	void roundTrip(string doc) {
		roundTripNode(parseVDF(doc));
	}
	roundTripNode(Node("key", "value"));
	roundTripNode(Node("root", [Node("key", "value"), Node("key2", "value2")]));
	roundTrip(`"empty" {}`);
	with(parseVDF(`"empty" {}`)) {
		assert(key == "empty");
		assert(conditional == "");
	}
	roundTrip(import("array.vdf"));
	{
		const node = parseVDF(import("array.vdf"));
		with(node) {
			assert(key == "array");
			assert(start.line == 1);
			assert(start.column == 1);
			assert(conditional == "");
			assert(length == 2);
			with(array[0]) {
				assert(key == "a");
				assert(str == "b");
				assert(start.line == 1);
				assert(start.column == 11);
			}
			with(array[1]) {
				assert(key == "c");
				assert(str == "d");
				assert(start.line == 1);
				assert(start.column == 19);
			}
		}
		assert("a" in node);
		assert("z" !in node);
		assert(node["a"] == "b");
	}
	roundTrip(import("array2.vdf"));
	with(parseVDF(import("array2.vdf"))) {
		assert(key == "a");
		assert(conditional == "");
		assert(str == "b");
	}
	roundTrip(import("ex1.vdf"));
	with(parseVDF(import("ex1.vdf"))) {
		assert(key == "someresource");
		assert(conditional == "$WIN");
		with(array[0]) {
			assert(key == "foo");
			assert(str == "bar");
		}
		with(array[1]) {
			assert(key == "odd");
			assert(str == "record");
		}
		with(array[2]) {
			assert(key == "someotherresource");
			with(array[0]) {
				assert(key == "baz");
				assert(str == "tar");
			}
		}
	}
	roundTrip(import("registry.vdf"));
	with(parseVDF(import("registry.vdf"))["HKCU"]["Software"]["Valve"]["Steam"]) {
		assert(length == 4);
		assert(array[0].length == 0);
		assert(array[0].key == "empty");
		assert(array[1].key == "steamglobal");
		assert(array[1]["language"] == "english");
		assert(array[1]["key"] == "42");

		assert(array[2][`double"quote`] == `ab"cd`);
		assert(array[2]["tab\tulator"] == "ab\tcd");
		assert(array[2]["new\nline"] == "ab\ncd");
		assert(array[2]["back\\slash"] == "ab\\cd");

		assert(array[3]["win32"] == "value");
		assert(array[3]["x360"] == "value");
	}
	with(parseVDF(`"empty"  ]`).collectException!VDFParserException.start) {
		assert(line == 1);
		assert(column == 10);
	}
	{
		string[string] arr;
		foreach (key, node; parseVDF(`"empty" {}`)) {
			arr[key] = node.str.idup;
		}
		assert(arr == null);
		foreach (key, node; parseVDF(`"keys" { "a" "b" "c" "d" }`)) {
			arr[key] = node.str.idup;
		}
		assert(arr == ["a": "b", "c": "d"]);
	}
	{
		string[string] arr;
		assert(arr == null);
		foreach (key, node; parseVDF(`"keys" { "subkey" { "a" "b" "c" "d" } }`)) {
			foreach (subkey, subnode; node) {
				arr[subkey] = subnode.str.idup;
			}
		}
		assert(arr == ["a": "b", "c": "d"]);
	}
}
