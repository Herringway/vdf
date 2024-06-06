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

union VDFData {
	enum Type
	{
	    none,
	    array,
	    string,
	    integer
	}
    static struct DataArray {
        VDFObject** data_value;
        size_t len;
    }
    DataArray data_array;

    const(char)[] data_string;

    long data_int;
}

struct VDFObject
{
    const(char)[] key;
    private VDFObject* parent;

    VDFData.Type type;
    VDFData data;
    const(char)[] conditional;

	size_t get_array_length() const
	    in(type == VDFData.Type.array)
	{
	    return data.data_array.len;
	}
	const(VDFObject)* index_array(const size_t index) const
	    in(type == VDFData.Type.array)
	    in(data.data_array.len > index)
	{
	    return data.data_array.data_value[index];
	}

	const(VDFObject)* index_array_str(const(char)[] str) const
	    in(type == VDFData.Type.array)
	    in(str != "")
	{
	    for (size_t i = 0; i < data.data_array.len; ++i)
	    {
	        const(VDFObject)* k = data.data_array.data_value[i];
	        if (k.key == str)
	            return k;
	    }
	    return null;
	}

	const(char)[] get_string()
	    in(type == VDFData.Type.string)
	{
	    return data.data_string;
	}

	long get_int()
	    in(type == VDFData.Type.integer)
	{
	    return data.data_int;
	}

	private void print_indent(const int l, void delegate(const char[]) @safe print) const
	{
	    const(char)[] spacing = "\t";

	    for (int k = 0; k < l; ++k)
	        print(spacing);

	    print("\"");
	    print_escaped(key, print);
	    print("\"");

	    switch (type)
	    {
	        case VDFData.Type.array:
	            print("\n");
	            for (int k = 0; k < l; ++k)
	                print(spacing);
	            print("{\n");
	            for (size_t i = 0; i < data.data_array.len; ++i)
	                data.data_array.data_value[i].print_indent(l+1, print);

	            for (int k = 0; k < l; ++k)
	                print(spacing);
	            print("}");
	            break;

	        case VDFData.Type.integer:
	            print.formattedWrite!"\t\t\"%d\""(data.data_int);
	            break;

	        case VDFData.Type.string:
	            print("\t\t\"");
	            print_escaped(data.data_string, print);
	            print("\"");
	            break;

	        default:
	        case VDFData.Type.none:
	            assert(0);
	            break;
	    }

	    if (conditional)
	        print.formattedWrite!"\t\t[%s]"(conditional.fromStringz);

	    print("\n");
	}

	void print(void delegate(const char[]) @safe print) const
	{
	    print_indent(0, print);
	}
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

VDFObject vdf_parse_buffer(const(char)[] buffer)
{
    assert(buffer, "No input");

    VDFObject root_object;
    root_object.key = null;
    root_object.parent = null;
    root_object.type = VDFData.Type.none;
    root_object.conditional = null;

    VDFObject* o = &root_object;

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
                        o.type = VDFData.Type.integer;
                    }
                    else
                    {
                        o.type = VDFData.Type.string;
                    }

                    switch (o.type)
                    {
                        case VDFData.Type.integer:
                        	auto tmpbuf = buf;
                            o.data.data_int = parse!long(tmpbuf, 10);
                            break;

                        case VDFData.Type.string:
                            o.data.data_string = local_strndup_escape(buf[0 .. len]);
                            break;

                        default:
                            assert(0);
                            break;
                    }

                    buf = null;

                    if (o.parent && o.parent.type == VDFData.Type.array)
                    {
                        o = o.parent;
                        assert(o.type == VDFData.Type.array);

                        o.data.data_array.len++;
                        o.data.data_array.data_value = cast(VDFObject**)realloc(o.data.data_array.data_value, ((void*).sizeof) * (o.data.data_array.len + 1));
                        o.data.data_array.data_value[o.data.data_array.len] = new VDFObject;
                        o.data.data_array.data_value[o.data.data_array.len].parent = o;

                        o = o.data.data_array.data_value[o.data.data_array.len];
                        o.key = null;
                        o.type = VDFData.Type.none;
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
                assert(o.type == VDFData.Type.none);

                if (o.parent && o.parent.type == VDFData.Type.array)
                    o.parent.data.data_array.len++;

                o.type = VDFData.Type.array;
                o.data.data_array.len = 0;
                o.data.data_array.data_value = cast(VDFObject**)malloc(((void*).sizeof) * (o.data.data_array.len + 1));
                o.data.data_array.data_value[o.data.data_array.len] = new VDFObject;
                o.data.data_array.data_value[o.data.data_array.len].parent = o;

                o = o.data.data_array.data_value[o.data.data_array.len];
                o.key = null;
                o.type = VDFData.Type.none;
                o.conditional = null;
                break;

            case CHAR_CLOSED_CURLY_BRACKET:
                assert(!buf);

                o = o.parent;
                assert(o);
                if (o.parent)
                {
                    o = o.parent;
                    assert(o.type == VDFData.Type.array);

                    o.data.data_array.data_value = cast(VDFObject**)realloc(o.data.data_array.data_value, ((void*).sizeof) * (o.data.data_array.len + 1));
                    o.data.data_array.data_value[o.data.data_array.len] = new VDFObject;
                    o.data.data_array.data_value[o.data.data_array.len].parent = o;

                    o = o.data.data_array.data_value[o.data.data_array.len];
                    o.key = null;
                    o.type = VDFData.Type.none;
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
                    VDFObject* prev = o.parent.data.data_array.data_value[o.parent.data.data_array.len-1];
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

VDFObject vdf_parse_file(const(char)[] path)
{
    return vdf_parse_buffer(readText(path));
}

void vdf_free_object(VDFObject* o)
{
    if (!o)
        return;

    switch (o.type)
    {
        case VDFData.Type.array:
            for (size_t i = 0; i <= o.data.data_array.len; ++i)
            {
                vdf_free_object(o.data.data_array.data_value[i]);
            }
            free(o.data.data_array.data_value);
            break;


        case VDFData.Type.string:
            break;

        default:
        case VDFData.Type.none:
            break;

    }

    free(o);
}

unittest {
	import std.array: Appender;
	Appender!(char[]) sink;
	immutable sample = import("registry.vdf");
	auto obj = vdf_parse_buffer(sample);
	obj.print((str) { sink ~= str; });
	assert(strip(sink.data) == strip(sample));
}
