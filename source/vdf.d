import core.stdc.stdlib;

import std.algorithm.mutation;
import std.ascii;
import std.conv;
import std.file;
import std.format;
import std.stdio;
import std.string;

enum CHAR_SPACE = ' ';
enum CHAR_TAB = '\t';
enum CHAR_NEWLINE = '\n';
enum CHAR_DOUBLE_QUOTE = '"';
enum CHAR_OPEN_CURLY_BRACKET = '{';
enum CHAR_CLOSED_CURLY_BRACKET = '}';
enum CHAR_OPEN_ANGLED_BRACKET = '[';
enum CHAR_CLOSED_ANGLED_BRACKET = ']';
enum CHAR_FRONTSLASH = '/';
enum CHAR_BACKSLASH = '\\';

enum FMT_UNKNOWN_CHAR = "Encountered Unknown Character %c (%li)\n";


enum vdf_data_type
{
    NONE,
    ARRAY,
    STRING,
    INT
}

union vdf_data {
    static struct DataArray {
        vdf_object** data_value;
        size_t len;
    }
    DataArray data_array;

    const(char)[] data_string;

    long data_int;
}

struct vdf_object
{
    const(char)[] key;
    private vdf_object* parent;

    vdf_data_type type;
    vdf_data data;

    const(char)[] conditional;
}

private const(char)[] local_strndup_escape(const(char)[] s)
{
    if (!s)
       return null;

    char[] retval = new char[](s.length + 1);
    retval[0 .. $ - 1] = s[];
    retval[$ - 1] = '\0';

    size_t pos;
    while (pos < retval.length)
    {
        if (retval[pos] == CHAR_BACKSLASH)
        {
        	const next = retval[pos + 1];
        	retval = retval.remove(pos);
            switch (next)
            {
                case 'n':
                    retval[pos] = CHAR_NEWLINE;
                    break;

                case 't':
                    retval[pos] = CHAR_TAB;
                    break;

                case CHAR_BACKSLASH:
                case CHAR_DOUBLE_QUOTE:
                    break;
               default: assert(0);
            }
        }
        pos++;
    }

    return retval;
}

unittest {
	assert(local_strndup_escape("abc") == "abc\0");
	assert(local_strndup_escape(`abc\n`) == "abc\n\0");
	assert(local_strndup_escape(`abc\t`) == "abc\t\0");
	assert(local_strndup_escape(`abc\"`) == "abc\"\0");
	assert(local_strndup_escape(`abc\\`) == "abc\\\0");
}

private void print_escaped(const(char)[] s, void delegate(const char[]) @safe print) @safe
{
    while ((s.length > 0) && s[0])
    {
        switch(s[0])
        {
            case CHAR_DOUBLE_QUOTE:
                print("\\\"");
                break;

            case CHAR_TAB:
                print("\\t");
                break;

            case CHAR_NEWLINE:
                print("\\n");
                break;

            case CHAR_BACKSLASH:
                print("\\\\");
                break;

            default:
                print(s[0 .. 1]);
                break;
        }

        s = s[1 .. $];
    }
}

unittest {
	import std.array : Appender;
	void runTest(string input, string expected) {
		Appender!(char[]) sink;
		print_escaped(input, (str) { sink ~= str; });
		assert(sink.data == expected);
	}
	runTest("Hello", `Hello`);
	runTest("oh\ta tab", `oh\ta tab`);
	runTest("\nnewline?", `\nnewline?`);
	runTest("a \\ (backslash)", `a \\ (backslash)`);
	runTest("some kinda \"quotes\"", `some kinda \"quotes\"`);
}

vdf_object vdf_parse_buffer(const(char)[] buffer)
{
    assert(buffer, "No input");

    vdf_object root_object;
    root_object.key = null;
    root_object.parent = null;
    root_object.type = vdf_data_type.NONE;
    root_object.conditional = null;

    vdf_object* o = &root_object;

    const(char)[] tail = buffer;

    const(char)[] buf = null;

    while (tail.length > 0)
    {
        switch (tail[0])
        {
            case CHAR_DOUBLE_QUOTE:
                if (tail.ptr > buffer.ptr && (tail.ptr-1)[0] == CHAR_BACKSLASH)
                    break;

                if (!buf)
                {
                    buf = tail[1 .. $];
                }
                else if (o.key)
                {
                    size_t len = &tail[0] - &buf[0];
                    size_t digits = 0;
                    size_t chars = 0;

                    for (size_t i = 0; i < len; ++i)
                    {
                        if (isDigit(buf[i]))
                            digits++;

                        if (isAlpha(buf[i]))
                            chars++;
                    }

                    if (len && digits == len)
                    {
                        o.type = vdf_data_type.INT;
                    }
                    else
                    {
                        o.type = vdf_data_type.STRING;
                    }

                    switch (o.type)
                    {
                        case vdf_data_type.INT:
                        	auto tmpbuf = buf;
                            o.data.data_int = parse!long(tmpbuf, 10);
                            break;

                        case vdf_data_type.STRING:
                            o.data.data_string = local_strndup_escape(buf[0 .. len]);
                            break;

                        default:
                            assert(0);
                            break;
                    }

                    buf = null;

                    if (o.parent && o.parent.type == vdf_data_type.ARRAY)
                    {
                        o = o.parent;
                        assert(o.type == vdf_data_type.ARRAY);

                        o.data.data_array.len++;
                        o.data.data_array.data_value = cast(vdf_object**)realloc(o.data.data_array.data_value, ((void*).sizeof) * (o.data.data_array.len + 1));
                        o.data.data_array.data_value[o.data.data_array.len] = new vdf_object;
                        o.data.data_array.data_value[o.data.data_array.len].parent = o;

                        o = o.data.data_array.data_value[o.data.data_array.len];
                        o.key = null;
                        o.type = vdf_data_type.NONE;
                        o.conditional = null;
                    }
                }
                else
                {
                    size_t len = &tail[0] - &buf[0];
                    o.key = local_strndup_escape(buf[0 .. len]);
                    buf = null;
                }
                break;

            case CHAR_OPEN_CURLY_BRACKET:
                assert(!buf);
                assert(o.type == vdf_data_type.NONE);

                if (o.parent && o.parent.type == vdf_data_type.ARRAY)
                    o.parent.data.data_array.len++;

                o.type = vdf_data_type.ARRAY;
                o.data.data_array.len = 0;
                o.data.data_array.data_value = cast(vdf_object**)malloc(((void*).sizeof) * (o.data.data_array.len + 1));
                o.data.data_array.data_value[o.data.data_array.len] = new vdf_object;
                o.data.data_array.data_value[o.data.data_array.len].parent = o;

                o = o.data.data_array.data_value[o.data.data_array.len];
                o.key = null;
                o.type = vdf_data_type.NONE;
                o.conditional = null;
                break;

            case CHAR_CLOSED_CURLY_BRACKET:
                assert(!buf);

                o = o.parent;
                assert(o);
                if (o.parent)
                {
                    o = o.parent;
                    assert(o.type == vdf_data_type.ARRAY);

                    o.data.data_array.data_value = cast(vdf_object**)realloc(o.data.data_array.data_value, ((void*).sizeof) * (o.data.data_array.len + 1));
                    o.data.data_array.data_value[o.data.data_array.len] = new vdf_object;
                    o.data.data_array.data_value[o.data.data_array.len].parent = o;

                    o = o.data.data_array.data_value[o.data.data_array.len];
                    o.key = null;
                    o.type = vdf_data_type.NONE;
                    o.conditional = null;
                }

                break;

            case CHAR_FRONTSLASH:
                if (!buf)
                    while (tail[0] != '\0' && tail[0] != CHAR_NEWLINE)
                        tail = tail[1 .. $];

                break;

            case CHAR_OPEN_ANGLED_BRACKET:
                if (!buf)
                {
                    vdf_object* prev = o.parent.data.data_array.data_value[o.parent.data.data_array.len-1];
                    assert(!prev.conditional);

                    buf = tail[1 .. $];

                    while (tail[0] != '\0' && tail[0] != CHAR_CLOSED_ANGLED_BRACKET)
                        tail = tail[1 .. $];

                    prev.conditional = local_strndup_escape(buf[0 .. &tail[0]-&buf[0]]);

                    buf = null;
                }

                break;

            default:
                assert(buf, "Invalid input");
                break;

            case CHAR_NEWLINE:
            case CHAR_SPACE:
            case CHAR_TAB:
                break;
        }
        tail = tail[1 .. $];
    }
    return root_object;
}

vdf_object vdf_parse_file(const(char)[] path)
{
    return vdf_parse_buffer(readText(path));
}


size_t vdf_object_get_array_length(const(vdf_object)* o)
{
    assert(o);
    assert(o.type == vdf_data_type.ARRAY);

    return o.data.data_array.len;
}

const(vdf_object)* vdf_object_index_array(const(vdf_object)* o, const size_t index)
{
    assert(o);
    assert(o.type == vdf_data_type.ARRAY);
    assert(o.data.data_array.len > index);

    return o.data.data_array.data_value[index];
}

const(vdf_object)* vdf_object_index_array_str(const(vdf_object)* o, const(char)[] str)
{
    if (!o || !str || o.type != vdf_data_type.ARRAY)
        return null;

    for (size_t i = 0; i < o.data.data_array.len; ++i)
    {
        const(vdf_object)* k = o.data.data_array.data_value[i];
        if (k.key == str)
            return k;
    }
    return null;
}

const(char)[] vdf_object_get_string(const(vdf_object)* o)
{
    assert(o.type == vdf_data_type.STRING);

    return o.data.data_string;
}

long vdf_object_get_int(const(vdf_object)* o)
{
    assert(o.type == vdf_data_type.INT);

    return o.data.data_int;
}

private void vdf_print_object_indent(const(vdf_object) o, const int l, void delegate(const char[]) @safe print)
{
    const(char)[] spacing = "\t";

    for (int k = 0; k < l; ++k)
        print(spacing);

    print("\"");
    print_escaped(o.key, print);
    print("\"");

    switch (o.type)
    {
        case vdf_data_type.ARRAY:
            print("\n");
            for (int k = 0; k < l; ++k)
                print(spacing);
            print("{\n");
            for (size_t i = 0; i < o.data.data_array.len; ++i)
                vdf_print_object_indent(*o.data.data_array.data_value[i], l+1, print);

            for (int k = 0; k < l; ++k)
                print(spacing);
            print("}");
            break;

        case vdf_data_type.INT:
            print.formattedWrite!"\t\t\"%d\""(o.data.data_int);
            break;

        case vdf_data_type.STRING:
            print("\t\t\"");
            print_escaped(o.data.data_string, print);
            print("\"");
            break;

        default:
        case vdf_data_type.NONE:
            assert(0);
            break;
    }

    if (o.conditional)
        print.formattedWrite!"\t\t[%s]"(o.conditional.fromStringz);

    print("\n");
}

void vdf_print_object(vdf_object o, void delegate(const char[]) @safe print = (str) { write(str); })
{
    vdf_print_object_indent(o, 0, print);
}

void vdf_free_object(vdf_object* o)
{
    if (!o)
        return;

    switch (o.type)
    {
        case vdf_data_type.ARRAY:
            for (size_t i = 0; i <= o.data.data_array.len; ++i)
            {
                vdf_free_object(o.data.data_array.data_value[i]);
            }
            free(o.data.data_array.data_value);
            break;


        case vdf_data_type.STRING:
            break;

        default:
        case vdf_data_type.NONE:
            break;

    }

    free(o);
}

unittest {
	import std.array: Appender;
	Appender!(char[]) sink;
	immutable sample = import("registry.vdf");
	auto obj = vdf_parse_buffer(sample);
	vdf_print_object_indent(obj, 0, (str) { sink ~= str; });
	assert(strip(sink.data) == strip(sample));
}