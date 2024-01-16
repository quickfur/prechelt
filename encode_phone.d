/**
 * Encoding phone numbers according to a dictionary.
 */
import std;

/**
 * Table of digit mappings.
 */
static immutable ubyte[dchar] digitOf;
shared static this()
{
    digitOf = [
        'E': 0,
        'J': 1, 'N': 1, 'Q': 1,
        'R': 2, 'W': 2, 'X': 2,
        'D': 3, 'S': 3, 'Y': 3,
        'F': 4, 'T': 4,
        'A': 5, 'M': 5,
        'C': 6, 'I': 6, 'V': 6,
        'B': 7, 'K': 7, 'U': 7,
        'L': 8, 'O': 8, 'P': 8,
        'G': 9, 'H': 9, 'Z': 9,
    ];
}

/**
 * Trie for storing dictionary words according to the phone number mapping.
 */
class Trie
{
    Trie[10] edges;
    string[] words;

    private void insert(string word, string suffix)
    {
        const(ubyte)* dig;
        while (!suffix.empty &&
               (dig = std.ascii.toUpper(suffix[0]) in digitOf) is null)
        {
            suffix = suffix[1 .. $];
        }

        if (suffix.empty)
        {
            words ~= word;
            return;
        }

        auto node = new Trie;
        auto idx = *dig;
        if (edges[idx] is null)
        {
            edges[idx] = new Trie;
        }
        edges[idx].insert(word, suffix[1 .. $]);
    }

    /**
     * Insert a word into the Trie.
     *
     * Characters that don't map to any digit are ignored in building the Trie.
     * However, the original form of the word will be retained as-is in the
     * leaf node.
     */
    void insert(string word)
    {
        insert(word, word[]);
    }

    /**
     * Iterate over all words stored in this Trie.
     */
    void foreachEntry(void delegate(string path, string word) cb)
    {
        void impl(Trie node, string path = "")
        {
            if (node is null) return;
            foreach (word; node.words)
            {
                cb(path, word);
            }
            foreach (i, child; node.edges)
            {
                impl(child, path ~ cast(char)('0' + i));
            }
        }
        impl(this);
    }
}

/**
 * Loads the given dictionary into a Trie.
 */
Trie loadDictionary(R)(R lines)
    if (isInputRange!R & is(ElementType!R : const(char)[]))
{
    Trie result = new Trie;
    foreach (line; lines)
    {
        result.insert(line.idup);
    }
    return result;
}

///
unittest
{
    auto dict = loadDictionary(q"ENDDICT
an
blau
Bo"
Boot
bo"s
da
Fee
fern
Fest
fort
je
jemand
mir
Mix
Mixer
Name
neu
o"d
Ort
so
Tor
Torf
Wasser
ENDDICT".splitLines);

    auto app = appender!(string[]);
    dict.foreachEntry((path, word) { app ~= format("%s: %s", path, word); });
    assert(app.data == [
        "10: je",
        "105513: jemand",
        "107: neu",
        "1550: Name",
        "253302: Wasser",
        "35: da",
        "38: so",
        "400: Fee",
        "4021: fern",
        "4034: Fest",
        "482: Tor",
        "4824: fort",
        "4824: Torf",
        "51: an",
        "562: mir",
        "562: Mix",
        "56202: Mixer",
        "78: Bo\"",
        "783: bo\"s",
        "7857: blau",
        "7884: Boot",
        "824: Ort",
        "83: o\"d"
    ]);
}

/**
 * Find all encodings of the given phoneNumber according to the given
 * dictionary, and write each encoding to the given sink.
 */
void findMatches(W)(Trie dict, const(char)[] phoneNumber, W sink)
    if (isOutputRange!(W, string))
{
    bool impl(Trie node, const(char)[] suffix, string[] path, bool allowDigit)
    {
        if (node is null)
            return false;

        // Ignore non-digit characters in phone number
        while (!suffix.empty && (suffix[0] < '0' || suffix[0] > '9'))
            suffix = suffix[1 .. $];

        if (suffix.empty)
        {
            // Found a match, print result
            foreach (word; node.words)
            {
                put(sink, format("%s: %-(%s %)", phoneNumber,
                                 path.chain(only(word))));
            }
            return !node.words.empty;
        }

        bool ret;
        foreach (word; node.words)
        {
            // Found a matching word, try to match the rest of the phone
            // number.
            if (impl(dict, suffix, path ~ word, true))
            {
                allowDigit = false;
                ret = true;
            }
        }

        if (impl(node.edges[suffix[0] - '0'], suffix[1 .. $], path, false))
        {
            allowDigit = false;
            ret = true;
        }

        if (allowDigit)
        {
            // If we got here, it means that if we take the current node as the
            // next word choice, then the following digit will have no further
            // matches, and we may encode it as a single digit.
            auto nextSuffix = suffix[1 .. $];
            if (nextSuffix.empty)
            {
                put(sink, format("%s: %-(%s %)", phoneNumber,
                                 path.chain(suffix[0 .. 1].only)));
                ret = true;
            }
            else
            {
                if (impl(dict, suffix[1 .. $], path ~ [ suffix[0] ], false))
                    ret = true;
            }
        }
        return ret;
    }

    impl(dict, phoneNumber[], [], true);
}

/**
 * Encode the given input range of phone numbers according to the given
 * dictionary, writing the output to the given sink.
 */
void encodePhoneNumbers(R,W)(R input, Trie dict, W sink)
    if (isInputRange!R & is(ElementType!R : const(char)[]) &&
        isOutputRange!(W, string))
{
    foreach (line; input)
    {
        findMatches(dict, line, sink);
    }
}

///
unittest
{
    auto dict = loadDictionary(q"ENDDICT
an
blau
Bo"
Boot
bo"s
da
Fee
fern
Fest
fort
je
jemand
mir
Mix
Mixer
Name
neu
o"d
Ort
so
Tor
Torf
Wasser
ENDDICT".splitLines);

    auto input = [
        "112",
        "5624-82",
        "4824",
        "0721/608-4067",
        "10/783--5",
        "1078-913-5",
        "381482",
        "04824",
    ];

    auto app = appender!(string[]);
    encodePhoneNumbers(input, dict, (string match) { app.put(match); });

    //writefln("%-(%s\n%)", app.data);
    assert(app.data.sort.release == [
        "04824: 0 Tor 4",
        "04824: 0 Torf",
        "04824: 0 fort",
        "10/783--5: je Bo\" da",
        "10/783--5: je bo\"s 5",
        "10/783--5: neu o\"d 5",
        "381482: so 1 Tor",
        "4824: Tor 4",
        "4824: Torf",
        "4824: fort",
        "5624-82: Mix Tor",
        "5624-82: mir Tor",
    ]);
}

/**
 * Program entry point.
 */
int main(string[] args)
{
    File input = stdin;
    bool countOnly;

    auto info = getopt(args,
        "c|count", "Count solutions only", &countOnly,
    );

    int showHelp()
    {
        stderr.writefln("Usage: %s [options] <dictfile> [<inputfile>]",
                        args[0]);
        defaultGetoptPrinter("", info.options);
        return 1;
    }

    if (info.helpWanted || args.length < 2)
        return showHelp();

    auto dictfile = args[1];
    if (args.length > 2)
        input = File(args[2]);

    Trie dict = loadDictionary(File(dictfile).byLine);

    if (countOnly)
    {
        size_t count;
        encodePhoneNumbers(input.byLine, dict, (string match) { count++; });
        writefln("Number of solutions: %d", count);
    }
    else
    {
        encodePhoneNumbers(input.byLine, dict, (string match) {
            writeln(match);
        });
    }

    return 0;
}

// vim:set sw=4 ts=4 et ai:
