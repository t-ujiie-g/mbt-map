// MoonBit for highlight.js (which has no MoonBit grammar): keywords, types, `@package` qualifiers,
// `#attributes`, strings with `\{…}` interpolation, `#|` raw lines and comments.

export default function moonbit(hljs) {
  return {
    name: "MoonBit",
    aliases: ["mbt"],
    keywords: {
      keyword:
        "fn let mut if else match for in while loop break continue return pub priv struct enum type trait impl extern test guard is raise noraise try catch async using as with derive suberror const defer extend",
      literal: "true false None Some Ok Err",
      built_in: "Int Int64 UInt UInt64 Double Float String Bool Char Byte Bytes Array FixedArray Map Json Unit Option Result Self Ref Error",
    },
    contains: [
      hljs.COMMENT(/\/\/\//, /$/),
      hljs.C_LINE_COMMENT_MODE,
      { scope: "string", begin: /#\|/, end: /$/ },
      { scope: "string", begin: /"/, end: /"/, contains: [{ scope: "subst", begin: /\\\{/, end: /\}/ }, hljs.BACKSLASH_ESCAPE] },
      { scope: "string", begin: /'(?:\\.|[^\\'])'/ },
      { scope: "symbol", begin: /@[a-z_][\w/]*/ },
      { scope: "meta", begin: /#[a-z_]+/ },
      { scope: "type", begin: /\b[A-Z]\w*/ },
      { scope: "title.function", begin: /\b[a-z_]\w*(?=\()/ },
      hljs.C_NUMBER_MODE,
    ],
  };
}
