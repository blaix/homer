# Claude Memory

This file contains shared memory and context for Claude Code across all hosts.

## Gren

Gren is a programming language similar to Elm.
Read the documentation at https://gren-lang.org/book/

IMPORTANT: There is no List type in Gren!

* The default sequential data type is an Array.
* Literal brackets will create arrays, not lists.
* All APIs are updated to use Arrays instead of lists.
* You should NEVER try to convert an array to a list.
* You NEVER need to use Array.fromList or similar.
  If you think you do, the API you're using probably wants an array anyway.
 
Other key differences to Elm are:

* The pattern matching syntax has changed from `case..of` to `when..is`
* There are no tuples. Where you would normally use a tuple in Elm, you should use a record in Gren.
* Pattern matching has extended to support records. Read the documentation at https://gren-lang.org/book/syntax/pattern_matching/ and https://gren-lang.org/book/syntax/destructuring/
* The unit type is `{}`, not `()`.
* There are no automatic constructors for type aliased records. You have to create your own functions.
* Custom type variants can only hold one value. If you need more than one, use a record.
* There are more modules for native web apis. See https://packages.gren-lang.org/package/gren-lang/browser and https://packages.gren-lang.org/package/gren-lang/core

Common function name differences from Elm:

* `Array.filter` does not exist - use `Array.keepIf` instead
* `Array.toList` does not exist - Arrays ARE the list type in Gren

Common gren commands:

* Compile a module: `gren make ModuleName` (usually `Main`)
* Run a module: `gren run ModuleName` (usually `Main`)
* Install packages with: `gren package install package/name`
* Create a gren browser application: `gren init`
* create a gren node application: `gren init --platform=node`
* Create a gren browser package: `gren init --package`
* Create a gren node package: `gren init --package --platform=node`
* Create a gren common package: `gren init --package --platform=common`

Devox:

* If there is a `devbox.json` in the project directory, you should prefix `gren` commands with `devbox run`. E.g. `devbox run gren make Main`
* Look at devbox.json for scripts like "build" and "test". If they exist, use those instead of the make commands above.

Common packages and APIs:

* Tests use https://packages.gren-lang.org/package/gren-lang/test/version/latest/overview
* Test effects with https://packages.gren-lang.org/package/blaix/gren-effectful-tests/version/latest/overview
* Browser API: https://packages.gren-lang.org/package/gren-lang/browser/version/latest/overview
* Html.Events API: https://packages.gren-lang.org/package/gren-lang/browser/version/latest/module/Html.Events
* Html.Keyed API: https://packages.gren-lang.org/package/gren-lang/browser/version/latest/module/Html.Keyed
* Node API: https://packages.gren-lang.org/package/gren-lang/node/version/latest/overview
* Array: https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/Array
* String: https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/String
* Dict: https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/Dict
* Bytes: https://packages.gren-lang.org/package/gren-lang/core/version/latest/module/Bytes
* PrettyNice web framework: https://github.com/blaix/prettynice
    * examples: https://github.com/blaix/prettynice/tree/main/examples/v3

Other things to remember about Gren:

* The program type for browser programs is just `Program` and does not need to be imported.
* Multi-line record updates should be formatted like this:
    ```
    { myRecord
        | field1 = "whatever"
        , field2 = "whatever"
    }
    ```
* Keyed nodes are available via `Html.Keyed.node` and take children as `Array { key : String, node : Html msg }`
* For custom event handlers with decoders, use `Html.Events.on "eventName" decoder`
* Use `Process.sleep` (takes milliseconds) with `Task.perform` to schedule delayed messages
* Math functions like `round`, `floor`, and `ceiling` are in the `Math` module, not global like in Elm
* String functions differ from Elm:
    * Use `String.count` instead of `String.length`
    * Use `String.takeLast` and `String.dropLast` instead of `String.right` and `String.dropRight`
* The `gren make` command uses module paths, not file paths:
    * Correct: `gren make Main`
    * Incorrect: `gren make src/Main.gren`

My Gren coding preferences:

* Favor fully qualified paths for functions in imported modules.
* Exception to the above point for Html.Events
* Favor aliasing nested modules to the leaf module name.
* Import Html as H
* Import Html.Attributes as A
* Forms should be actual forms using onSubmit, instead of an onClick on the submit button.
* Prefer past-tense verbs for message names. E.g. `InputUpdated` instead of `UpdateInput`

## Python

* I use nix. The python interpreter should be on my path at `/run/current-system/sw/bin/python`
* When you need to install python packages, prefer local virtualenvs, using the built-in python functionality for this (`python -m venv ./.venv && source ./.venv/bin/activate`)
* To install missing python modules/packages, use pip after activating the local virtualenv.
* Python scripts should be run with python explicitly, not with a shebang line in the script, so the local venv is picked up.
