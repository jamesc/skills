---
name: use-lsp
description: Use when navigating code, finding references, looking up definitions, understanding types, or tracing call hierarchies in TypeScript or Rust files. Prefer LSP over Grep/Glob for any navigation task where symbol semantics matter.
---

# Use LSP for Code Navigation

## Overview

The `LSP` tool provides semantic code intelligence. Use it instead of text search whenever you need to navigate by *meaning* (what calls this, what does this return, where is this defined) rather than by *text* (find this string in files).

## When to Use LSP vs Grep

| Task | Use |
|------|-----|
| Find where a function is defined | `LSP goToDefinition` |
| Find all call sites of a function | `LSP findReferences` |
| Understand a type / see docs | `LSP hover` |
| Find all methods on a type | `LSP documentSymbol` |
| Search for a symbol by name | `LSP workspaceSymbol` |
| Find implementations of a trait/interface | `LSP goToImplementation` |
| Understand call chains | `LSP incomingCalls` / `outgoingCalls` |
| Find a file by name pattern | `Glob` |
| Search for a string/regex in files | `Grep` |
| Find all uses of a string literal | `Grep` |

## Red Flags — You're Using the Wrong Tool

- Running `Grep` for a function name to find its callers → use `LSP findReferences`
- Running `Grep` for a struct/class name to find its definition → use `LSP goToDefinition`
- Reading a whole file to understand what a function returns → use `LSP hover`
- Running `Grep` for a type name to find implementations → use `LSP goToImplementation`

## Usage

All LSP operations require `filePath`, `line`, and `character` (1-based). Get these from a prior `Read` or `Grep` result.

```
LSP goToDefinition    filePath, line, character
LSP findReferences    filePath, line, character
LSP hover             filePath, line, character
LSP documentSymbol    filePath, line, character  (any position in file)
LSP workspaceSymbol   filePath, line, character  (query via name)
LSP goToImplementation filePath, line, character
LSP incomingCalls     filePath, line, character
LSP outgoingCalls     filePath, line, character
```

## Common Mistake

Using `Grep` to find all usages of a function, then reading each file to understand context. Instead:

1. `Grep` once to find one occurrence and get file+line
2. `LSP findReferences` to get all call sites with precise positions
3. `LSP hover` at any site to understand types/docs without reading the file

## Limitations

- LSP requires the language server to be running (rust-analyzer for Rust, tsserver for TypeScript)
- If LSP returns no results, fall back to `Grep` — the server may not have indexed the file yet
- LSP works on committed or saved files; unsaved edits may not be reflected immediately
