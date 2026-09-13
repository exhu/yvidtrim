# D Coding style
Prefered coding style is slightly different from standard D style. It's similar in default clang: indentation is 2 spaces, opening { is on the same line as struct/class/function/if/while etc. declaration.

## File naming
All source file names are always lower case.

## D symbol names
D code symbol names use D style naming rules, e.g. all module names lowercase, types, classes in PascalCase; consts, variables, functions/methods, fields, enum values in camelCase.

## D null handling
By default reference types (classes) and pointers passed to functions and in
return values cannot be null. If they are allowed to be null it must be
documented in the comment to the function/method. Insert `assert(argument !is
null)` in constructors where necessary.

If a struct or class field must not be null in all cases, add struct or class
`invariant` block with `assert(field !is null)` instead of silently creating
empty objects, or placing null checks everywhere. Disable default constructor if
the field must be initialized via an argument to a non-null value.

## Resources and string import
Essencial static resources like fonts, images, shaders, texts are embedded into
final program via D's import strings.

# C coding style
C code uses the same formatting: 2 spaces, open curly brance on the same line.

## C symbol names
Types/enums in PascalCase; defines, enum values, public consts in upper
SNAKE_CASE, variables, consts, function names in snake\_case.

However public functions and types get prefixed with a library name in the
lower snake case, while enum/defines/constants have library prefix all upper case, e.g.
```c
typedef struct my_lib_UserProfile {
  const char* user_name;
  const char* address_line;
} my_lib_UserProfile;

typedef enum my_lib_WindowStyle {
  MY_LIB_WINDOW_STYLE_NONE,
  MY_LIB_WINDOW_STYLE_RESIZEABLE,
} my_lib_WindowStyle;

```
