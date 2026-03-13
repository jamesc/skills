---
name: explain
description: Create a walkthrough document for code, a pattern, or a feature. Prompts the user for walkthrough style (demo, linear, architecture, API reference, ...) and produces the appropriate document using showboat or plain markdown.
argument-hint: [file, directory, or topic]
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
---

# Explain

The user wants a walkthrough of: **$ARGUMENTS**

## Step 1 — ask what kind of walkthrough they want

Use AskUserQuestion to ask:

> "What kind of walkthrough would you like?"

Options:
- **Demo** — interactive showboat document: code snippets pulled with `sed`, executable blocks, verified output. Best for a library, pattern, or module the reader will run themselves.
- **Linear** — narrative prose walking through the code top-to-bottom: reads each file in order, explains every method and decision. Best for onboarding someone to unfamiliar code.
- **Architecture** — high-level overview: components, responsibilities, data flow, key decisions. No line-by-line code; uses diagrams (ASCII) where helpful. Best for understanding the big picture.
- **API Reference** — method-by-method catalogue: signature, purpose, parameters, return value, example call. Best as a quick-look reference for callers.

Also ask where to save the output (default: `README.md` next to the subject, or a name they specify).

## Step 2 — explore the subject

Read the relevant source files. For directories, glob all `.bt` (or relevant language) files. Note:
- Class/module names and their responsibilities
- Public methods and their signatures (doc comments)
- Key algorithms or patterns
- Test files (infer from path conventions, e.g. `test/<pattern>/`)

## Step 3 — produce the walkthrough

### Demo (showboat)

Use `uvx showboat` to build an executable document. Standard section order:

1. **Intent** — one paragraph stating what this code does and why
2. **The Players** — one subsection per class/file; `exec bash sed -n 'X,Yp' <file>` to show the code
3. **How [Language] Features Help** — 4–6 bullet points calling out specific language idioms
4. **Walking Through the Tests** — 3–5 tests shown with `exec bash sed`, each preceded by a `note` explaining what it proves
5. **Running the Tests** — `exec bash echo` block listing all test names as PASS + summary line

Run with `--workdir <directory-of-the-output-file>` so paths are relative.
Finish with `uvx showboat verify --workdir <dir> <file>` and fix any failures before declaring done.

Rules:
- All paths in exec blocks must be relative to the output file's directory
- Use `sed -n 'X,Yp'` to pull specific line ranges — never cat whole files
- Quote showboat `note` arguments in single quotes to prevent shell expansion of backticks and special characters
- Test exec output blocks with `echo` (never actually run the test suite live in the document)

### Linear

Write a plain markdown document. Walk through each file in dependency order (base classes before subclasses). For each file:
- One-sentence purpose statement
- Code block (full file or key excerpts if large)
- Prose explaining each method: what it does, why it's written that way, any non-obvious decisions

End with a "Putting it together" section showing how the pieces compose.

### Architecture

Write a plain markdown document with:
1. **Overview** — 2–3 sentences: what this subsystem does, where it fits
2. **Component Map** — ASCII diagram of classes/modules and their relationships (arrows for calls/inheritance)
3. **Responsibilities** — bullet list, one line per component
4. **Data Flow** — numbered steps tracing a representative request through the system
5. **Key Decisions** — 3–5 design choices worth noting, with brief rationale

### API Reference

Write a plain markdown document. One `###` section per public method:
```
### methodName: param
**Signature:** `Class >> methodName: aParam`
**Purpose:** One sentence.
**Parameters:** `aParam` — what it is.
**Returns:** what comes back.
**Example:**
    result := obj methodName: value
```

## Step 4 — save and confirm

Write the document to the agreed path. Tell the user where it was saved and (for demo type) whether `showboat verify` passed.
