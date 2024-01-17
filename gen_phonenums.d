/**
 * Generate random phone numbers.
 */
import std;

void main(string[] args)
{
    size_t maxlen = 50;
    size_t n = 10_000;

    if (args.length > 1)
        n = args[1].to!size_t;

    if (args.length > 2)
        maxlen = args[2].to!size_t;

    foreach (_; 0 .. n)
    {
        static immutable chars = "0123456789/-";
        auto len = uniform(1, maxlen + 1);
        auto result = iota(0, len)
            .map!(i => chars[uniform(0, chars.length)])
            .array;
        writeln(result);
    }
}

// vim:set sw=4 ts=4 et ai:
