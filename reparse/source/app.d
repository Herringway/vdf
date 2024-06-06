import std.stdio;

import vdf;

int main(string[] args)
{
    File output = stdout;
    if (args.length < 2)
    {
        puts("vdf_reparse file [output]");
        return 1;
    }
    else if (args.length > 2)
    {
        output = File(args[2], "w");
    }

    vdf_parse_file(args[1]).print((str) { output.write(str); });
    return 0;
}
