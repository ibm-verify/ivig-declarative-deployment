# Guidelines for contributors

## Documentation, Code Style and Commenting

### Standalone documentation

Documentation should be authored in [markdown](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax).
Markdown files must be encoded as UTF-8 without byte order mark. Lines should be
terminated by a single line feed rather than CR/LF.

We explicitly discourage creating documentation in proprietary file formats used
by popular office suites, and recommend [Pandoc, a universal document converter
](https://pandoc.org) to convert from markdown to other formats if needed.

If any other form of documentation is uploaded, make sure you place the source
under version control. For example, all pixel-based images exported from diagram
drawing tools or vector based editors should be uploaded together with
respective source files. Similarly, PDFs should be accompanied by their
respective sources. All parts of the documentation needs to be reproducible, and
the names and versions of editors used (i.e. diagram drawing tools) need to be
recorded at least in a flat text file.

The **README.md** file in the repository root serves as the main entry point and
should provide a clear overview of project scope, goals, and high level
scenarios, and refer to other documentation artifacts under the `docs` folder.
Images referenced from **README.md** shall also be stored under `docs`.

### Source Code

#### General Formatting Rules

**Readability is the top priority.** These guidelines exist to serve that goal,
not the other way around. Any rule below may be bent when following it strictly
would make the code harder to understand — use your judgement and leave a brief
comment if the deviation is not self-evident.

When editing an existing file, adapt to the style already present in that file
rather than mechanically applying these rules. Consistency within a file
outweighs project-wide uniformity.

All source files must otherwise follow these baseline rules regardless of
language:

- **Encoding**: UTF-8 without byte order mark (BOM). Prefer plain ASCII
  characters wherever possible; use Unicode only when the content genuinely
  requires it (e.g. string literals containing non-Latin text).
- **Indentation**: Two spaces per level. Tabs are not permitted anywhere in
  source files.
- **Line endings**: Unix-style line feed (`\n`). Do not commit files with
  Windows-style CR/LF (`\r\n`) line endings.
- **Trailing whitespace**: No trailing spaces or tabs at the end of any line.
- **Final newline**: Every file must end with exactly one newline character.
- **Line length**: There is no hard limit for code lines. Comments and inline
  documentation must be hard-wrapped at 80 columns. Never break a code line
  solely to meet a column count if doing so hurts readability. URLs, long string
  literals, and generated or structured content are exempt from the 80-column
  rule even inside comments.

#### Bash

- Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
  as the baseline reference.
- Use two-space indentation (consistent with the general rule above).
- Always start scripts with a shebang.
- **Bash 3.2 compatibility**: Do not use features introduced after Bash 3.2.
- Do not introduce new dependencies, use bash built-ins rather than external
  commands.
- Maintain compatibility with GNU and BSD tools and respect the stated minimum
  versions required, e.g. sed (GNU 4.2, BSD) and grep (GNU 3.6, BSD 2.6).
- Prefer `[[ ]]` for conditionals rather than `[ ]`.
- Quote all variable expansions (`"${VAR}"`) unless word-splitting or globbing
  is explicitly intended.
- Use `$()` for command substitution, never backticks.
- **Variable naming**: All variables must use `UPPER_SNAKE_CASE`, including
  local script variables.
- **Script documentation**: Every script must include one of the following:
  - A short comment block at the top of the file (after the shebang) describing
    purpose, expected inputs, and any side-effects; or
  - A `usage()` function that prints a description and at least one usage
    example, called automatically when the script is invoked with `-h` or
    `--help` or with invalid arguments.

#### Helm

- Use two-space indentation in all templates and plain YAML files.
- Indent template actions to match the YAML structure they belong to,
  regardless of whitespace trimming:
  ```yaml
  spec:
    {{- if not .Values.isOpenShift }}
    securityContext:
      fsGroup: {{ .Values.services.mqshare.group }}
    {{- end }}
  ```
- Use `nindent` (rather than `indent`) when piping multi-line values into a
  template so that the leading newline is included and the YAML indentation
  stays consistent:
  ```yaml
  {{- if .Values.oidc}}
  oidc: {{- .Values.oidc | toYaml | nindent 2 }}
  {{- end }}
- Strip whitespace (`{{-` / `-}}`) deliberately and consistently. Prefer
  trimming only the side that would otherwise produce a stray blank line;
  do not strip both sides blindly, as this can collapse intentional blank
  lines in the output.
- Keep template expressions compact and readable.
- Use named templates (`define`/`include`) to encapsulate complexity and avoid
  duplicated logic. Every named template must have a comment directly above its
  `{{- define ... }}` line describing what it renders and what context (`.`) it
  expects, along with a usage example.
- Provide reasonable defaults for values referenced in templates and ensure
  proper error handling.

## Testing

At minimum, manually verify your changes work as intended and briefly describe
how you tested them in the pull request description.

## Git Commit Messages

This project prefers to keep a clean commit history with well-formed commit
messages on the master branch, however, commit messages on feature branches are
handled more liberally.  This section illustrates a model commit message and
provides some explanation.

Here’s a model Git commit message:

```text
Short (50 chars or less) summary of changes

More detailed explanatory text, if necessary.  It is preferred to wrap
it to 72 characters.  In some contexts, the first line is treated as the
subject of an email and the rest of the text as the body.  The blank
line separating the summary from the body is critical (unless you omit
the body entirely); tools like rebase can get confused if you run the
two together.

Write your commit message in the present tense: "Fix bug", not "Fixed
bug".  This convention matches up with commit messages generated by
commands like git merge and git revert.

Further paragraphs come after blank lines.

- Bullet points are okay, too
- Typically a hyphen or asterisk is used for the bullet, preceded by a
  single space, with blank lines in between, but conventions vary here
- Use a hanging indent
```

Here are some of the reasons why wrapping your commit messages to 72 columns is
preferred.

- git log doesn't perform any special wrapping of the commit messages. With the
  default pager of `less -S`, this means your paragraphs flow far off the edge
  of the screen, making them difficult to read. On an 80 column terminal, if we
  subtract 4 columns for the indent on the left and 4 more for symmetry on the
  right, we’re left with 72 columns.
- git format-patch --stdout converts a series of commits to a series of emails,
  using the messages for the message body.  Good email netiquette dictates we
  wrap our plain text emails such that there’s room for a few levels of nested
  reply indicators without overflow in an 80 column terminal.

If you use an issue tracker, add a reference(s) to them at the bottom,
like so: `Resolves: #123`

## Code Approval Process

This section describes the code approval process that is used for code
contributions.  This is how to get your changes into the project.

### Work on Feature Branches

Contributors are expected to work on feature branches and submit pull requests
when they feel their feature or bug fix is ready for integration into the master
branch.

We firmly believe in the share early, share often approach.  The basic premise
of the approach is to announce your plans **before** you start work (preferably
by opening an issue), and once you have started working, craft your changes into
a stream of small and easy to review commits on your feature branch.

This approach has several benefits:

- Announcing your plans to work on a feature **before** you begin work avoids
  duplicate work
- It permits discussions which can help you achieve your goals in a way that is
  consistent with the existing architecture
- It minimizes the chances of you spending time and energy on a change that
  might not fit with the consensus of the team or existing architecture and
  potentially be rejected as a result
- Incremental development helps ensure you are on the right track with regards
  to the rest of the community
- The quicker your changes are merged to master, the less time you will need to
  spend rebasing and otherwise trying to keep up with the main code base

### Code Review

All code which is submitted will need to be reviewed before inclusion into the
master branch.  This process is performed by the project owner and mentors.

### Rework Code (if needed)

After the code review, the change will be accepted immediately if no issues are
found.  If there are any concerns or questions, you will be provided with
feedback along with the next steps needed to get your contribution merged into
master.  In certain cases the code reviewer(s) or interested committers may help
you rework the code, but generally you will simply be given feedback for you to
make the necessary changes.

This process will continue until the code is finally accepted.

### Acceptance

Once your code is accepted, it will be integrated with the master branch.
Typically it will be squash merged, which combines all commits from your feature
branch into a single commit in the base branch to keep a clean commit history
over a tangled weave of merge commits.  Regardless of the specific merge method
used, the code will be integrated with the master branch and the pull request
will be closed.

