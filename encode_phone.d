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

alias MatchCallback = void delegate(const(char)[] phone, const(char)[] match);

/**
 * Find all encodings of the given phoneNumber according to the given
 * dictionary, and write each encoding to the given sink.
 */
void findMatches(Trie dict, const(char)[] phoneNumber, MatchCallback cb)
{
    /*
     * Optimization: use a common buffer for constructing the output string,
     * instead of using string append, which allocates many new strings.
     *
     * The `path` parameter passed to .impl is always a slice of .buffer,
     * either its current instance or a previous instance left over from a
     * buffer reallocation. As such, its contents are always an initial segment
     * of whatever's in .buffer, so appending is just a matter of writing to
     * the tail end of the buffer and returning a slice of the new buffer.
     *
     * The fact that .path higher up the call tree may be pointing to old
     * versions of .buffer is not a problem; contentwise they are always an
     * initial segment of the current .buffer, so any subsequent appends will
     * copy the new word to the right place in the current .buffer and return a
     * slice to it, and the contents will always be consistent.
     */
    static char[] buffer;
    const(char)[] appendPath(const(char)[] path, const(char)[] word)
    {
        // Assumption: path is an initial segment of buffer (either its current
        // incarnation or a pre-reallocated initial copy). So we don't need to
        // copy the initial segment, just whatever needs to be appended.
        if (path.length == 0)
        {
            auto newlen = word.length;
            if (buffer.length < newlen)
                buffer.length = newlen;
            buffer[0 .. newlen] = word[];
            return buffer[0 .. newlen];
        }
        else
        {
            auto newlen = path.length + 1 + word.length;
            if (buffer.length < newlen)
                buffer.length = newlen;
            buffer[path.length] = ' ';
            buffer[path.length + 1 .. newlen] = word[];
            return buffer[0 .. newlen];
        }
    }

    bool impl(Trie node, const(char)[] suffix, const(char)[] path,
              bool allowDigit)
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
                cb(phoneNumber, appendPath(path, word));
            }
            return !node.words.empty;
        }

        bool ret;
        foreach (word; node.words)
        {
            // Found a matching word, try to match the rest of the phone
            // number.
            ret = true;
            if (impl(dict, suffix, appendPath(path, word), true))
                allowDigit = false;
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
                cb(phoneNumber, appendPath(path, suffix[0 .. 1]));
                ret = true;
            }
            else
            {
                if (impl(dict, suffix[1 .. $],
                         appendPath(path, suffix[0 .. 1]), false))
                    ret = true;
            }
        }
        return ret;
    }

    // Trim trailing non-digits from phone number
    auto suffix = phoneNumber[];
    while (!suffix.empty && (suffix[$-1] < '0' || suffix[$-1] > '9'))
    {
        suffix = suffix[0 .. $-1];
    }

    impl(dict, suffix, buffer[0 .. 0], true);
}

/**
 * Encode the given input range of phone numbers according to the given
 * dictionary, writing the output to the given sink.
 */
void encodePhoneNumbers(R)(R input, Trie dict, MatchCallback cb)
    if (isInputRange!R & is(ElementType!R : const(char)[]))
{
    foreach (line; input)
    {
        findMatches(dict, line, cb);
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
    encodePhoneNumbers(input, dict, (phone, match) {
        app.put(format("%s: %s", phone, match));
    });

    //writefln("\n%-(%s\n%)", app.data);
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

unittest
{
    auto dict = loadDictionary(q"ENDDICT
Bias
ja
Mai
Reck
Weib
USA
ENDDICT".splitLines);

    auto input = [
        "/7-357653152/0677-",
        "/7-3576-",
        "/8-",
        "1556/0",
    ];

    auto app = appender!(string[]);
    encodePhoneNumbers(input, dict, (phone, match) {
        app.put(format("%s: %s", phone, match));
    });

    //writefln("\n%-(%s\n%)", app.data);
    assert(app.data.sort.release == [
        "/7-357653152/0677-: USA Bias ja Reck 7",
        "/7-357653152/0677-: USA Bias ja Weib 7",
        "/8-: 8",

        /* Note: 1556/0 should NOT encode as "1 Mai 0" because the initial "15"
         * matches "ja", thus excluding a digit in that position. */
    ]);
}

/**
 * Program entry point.
 */
int main(string[] args)
{
    File input = stdin;
    auto dictfile = "tests/words.txt";
    bool countOnly;

    int showHelp()
    {
        stderr.writefln("Usage: %s <count|print> <dictfile> [<inputfile>]",
                        args[0]);
        return 1;
    }

    if (args.length > 1)
    {
        if (args[1] == "-h")
            return showHelp();
        else if (args[1] == "count")
            countOnly = true;
    }
    if (args.length > 2)
        dictfile = args[2];
    if (args.length > 3)
        input = File(args[3]);

    Trie dict = loadDictionary(File(dictfile).byLine);

    if (countOnly)
    {
        size_t count;
        encodePhoneNumbers(input.byLine, dict, (phone, match) { count++; });
        writefln("%d", count);
    }
    else
    {
        encodePhoneNumbers(input.byLine, dict, (phone, match) {
            writefln("%s: %s", phone, match);
        });
    }

    return 0;
}

// vim:set sw=4 ts=4 et ai:
