# Claude Memory

This file contains shared memory and context for Claude Code across all hosts.

## Gren

Gren is a programming language similar to Elm.
Read the documentation at https://gren-lang.org/book/

The key differences to Elm are:

* There is no List type. The default sequential data type is an Array. Literal brackets will create arrays, not lists.
* The Array API has changed. Find the available array functions at https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/Array
* The String API has changed. Find the available string functions at https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/String
* The Dict API has changed. Find the available dict functions at https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/Dict
* The pattern matching syntax has changed from `case..of` to `when..is`
* There are no tuples. Where you would normally use a tuple in Elm, you should use a record in Gren.
* Pattern matching has extended to support records. Read the documentation at https://gren-lang.org/book/syntax/pattern_matching/ and https://gren-lang.org/book/syntax/destructuring/
* The unit type is `{}`, not `()`.
* There are no automatic constructors for type aliased records. You have to create your own functions.
* Custom type variants can only hold one value. If you need more than one, use a record.

Common gren commands:

* Compile a module: `gren make ModuleName` (usually `Main`)
* Run a module: `gren run ModuleName` (usually `Main`)

Common packages and APIs:

* Tests use https://packages.gren-lang.org/package/gren-lang/test/version/latest/overview
* Test effects with https://packages.gren-lang.org/package/blaix/gren-effectful-tests/version/latest/overview
* Browser API: https://packages.gren-lang.org/package/gren-lang/browser/version/latest/overview
* Node API: https://packages.gren-lang.org/package/gren-lang/node/version/latest/overview
* PrettyNice web framework: https://github.com/blaix/prettynice
    * examples: https://github.com/blaix/prettynice/tree/main/examples/v3
