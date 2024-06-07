module vdf.tokenizer;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.ascii;
import std.exception;
import std.typecons;
import std.range;

import vdf.common;

struct Token {
	enum Type {
		scalar,
		curlyLeft,
		curlyRight,
		braceLeft,
		braceRight,
		comment,
		endOfDocument,
	}
	Type type;
	const(char)[] text;
	Mark start;
}

struct Tokenizer {
	private const(char)[] buffer;
	private Mark mark;
	private bool startedBracketToken;
	Token front;
	bool empty;
	this(const char[] buffer, string name = "<unknown>") @safe pure {
		this.buffer = buffer;
		this.mark = Mark(name, 1, 1); // 1-based, not 0
		popFront();
	}
	void popFront() @safe pure {
		while ((buffer.length > 0) && buffer[0].isWhite) {
			mark.column++;
			if (buffer[0].among('\n', '\r')) {
				mark.line++;
				mark.column = 1;
			}
			buffer = buffer[1 .. $];
		}
		if (buffer.length == 0) {
			if (front.type == Token.Type.endOfDocument) {
				empty = true;
			}
			front = Token(Token.Type.endOfDocument, [], mark);
			return;
		}
		debug(tokenizer) scope(exit) { import std.logger; infof("Next: %s", front); }
		switch (buffer[0]) {
			case '[':
				startedBracketToken = true;
				front = Token(Token.Type.braceLeft, buffer[0 .. 1], mark);
				buffer = buffer[1 .. $];
				mark.column++;
				break;
			case ']':
				startedBracketToken = false;
				front = Token(Token.Type.braceRight, buffer[0 .. 1], mark);
				buffer = buffer[1 .. $];
				mark.column++;
				break;
			case '{':
				front = Token(Token.Type.curlyLeft, buffer[0 .. 1], mark);
				buffer = buffer[1 .. $];
				mark.column++;
				break;
			case '}':
				front = Token(Token.Type.curlyRight, buffer[0 .. 1], mark);
				buffer = buffer[1 .. $];
				mark.column++;
				break;
			case '/':
				enforce((buffer.length > 1) && (buffer[1] == '/'), new VDFTokenizationException(mark, "Malformed comment"));
				const endOfLine = buffer.countUntil!(x => !!x.among('\n', '\r'));
				const commentLength = endOfLine == -1 ? buffer.length : endOfLine;
				front = Token(Token.Type.comment, buffer[0 .. commentLength], mark);
				buffer = buffer[commentLength .. $];
				mark.column += commentLength;
				break;
			case '"':
				bool skipQuote;
				foreach (idx, pair; buffer[1 .. $].chain(only(' ')).slide(2).enumerate) {
					if (!skipQuote && (pair.front == '"')) {
						front = Token(Token.Type.scalar, buffer[0 .. idx + 2], mark);
						buffer = buffer[idx + 2 .. $];
						mark.column += idx + 2;
						return;
					}
					skipQuote = pair.front == '\\';
				}
				throw new VDFTokenizationException(mark, "Malformed scalar");
				break;
			default:
				if (startedBracketToken) {
					foreach (idx, chr; buffer) {
						if (chr == ']') {
							front = Token(Token.Type.scalar, buffer[0 .. idx], mark);
							buffer = buffer[idx .. $];
							mark.column += idx;
							return;
						}
					}
					throw new VDFTokenizationException(mark, "Malformed scalar");
				} else {
					throw new VDFTokenizationException(mark, "Unknown character: " ~ buffer[0]);
				}
		}
	}
	inout(Tokenizer) save() inout @safe pure {
		return this;
	}
}

@safe pure unittest {
	import std.array : array;
	void assertMark(string doc, ulong expectedLine, ulong expectedColumn) {
		with(Tokenizer(doc).array.collectException!VDFException.start) {
			assert(line == expectedLine);
			assert(column == expectedColumn);
		}
	}
	assert(Tokenizer("").array == [
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 1, 1))
	]);
	assert(Tokenizer("  \t    \n   ").array == [
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 2, 4))
	]);
	assert(Tokenizer("{}").array == [
		Token(Token.Type.curlyLeft, "{", Mark("<unknown>", 1, 1)),
		Token(Token.Type.curlyRight, "}", Mark("<unknown>", 1, 2)),
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 1, 3)),
	]);
	assertMark("/", 1, 1);
	assertMark("?", 1, 1);
	assertMark("[hello", 1, 2);
	assertMark(`"hello`, 1, 1);
	assert(Tokenizer("// comment without newline").array == [
		Token(Token.Type.comment, "// comment without newline", Mark("<unknown>", 1, 1)),
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 1, 27)),
	]);
	assert(Tokenizer("// comment with newline\n").array == [
		Token(Token.Type.comment, "// comment with newline", Mark("<unknown>", 1, 1)),
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 2, 1)),
	]);
	assert(Tokenizer(`"value"`).array == [
		Token(Token.Type.scalar, `"value"`, Mark("<unknown>", 1, 1)),
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 1, 8)),
	]);
	assert(Tokenizer(`"value\"with\"escapes"`).array == [
		Token(Token.Type.scalar, `"value\"with\"escapes"`, Mark("<unknown>", 1, 1)),
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 1, 23)),
	]);
	assert(Tokenizer(`"win32"		"value"		[$WIN32]`).array == [
		Token(Token.Type.scalar, `"win32"`, Mark("<unknown>", 1, 1)),
		Token(Token.Type.scalar, `"value"`, Mark("<unknown>", 1, 10)),
		Token(Token.Type.braceLeft, "[", Mark("<unknown>", 1, 19)),
		Token(Token.Type.scalar, `$WIN32`, Mark("<unknown>", 1, 20)),
		Token(Token.Type.braceRight, "]", Mark("<unknown>", 1, 26)),
		Token(Token.Type.endOfDocument, "", Mark("<unknown>", 1, 27)),
	]);
}
