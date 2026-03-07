---
name: review-code
description: Review current branch changes vs main. Use when user types /review-code or asks for a code review of their changes.
model: claude-opus-4-6
---

# Code Review Workflow

A **three-pass code review** that progressively deepens analysis. Each pass uses a different lens to catch issues the previous pass missed.

**Key Philosophy:** Complete improvements during review rather than deferring to future PRs. If something can be done well in <2 hours, implement it now. The goal is to ship excellent code the first time.

## Invocation

```
/review-code              # Review current branch vs main
/review-code BT-123       # Find PR for Linear issue, checkout, review
/review-code #225         # Checkout PR #225, review
```

**When a Linear issue or PR number is provided:**
1. Find the associated PR: `gh pr list --repo jamesc/beamtalk --search "BT-123" --json number,headRefName`
2. Checkout the branch: `gh pr checkout <number>`
3. Proceed with the review

---

## Review Depth

Not every PR needs 3 passes. Auto-scale based on change size and type:

```bash
# Count changed lines (additions + deletions)
git --no-pager diff --shortstat $(git merge-base HEAD origin/main)..HEAD
```

| Change Size | Criteria | Passes | Rationale |
|-------------|----------|--------|-----------|
| **Small** | <50 lines changed, or docs/skills/config only | Pass 1 only | Surface review is sufficient |
| **Medium** | 50-300 lines, touches 1-2 components | Pass 1 + Pass 2 | Cross-component checks needed |
| **Large** | >300 lines, touches 3+ components, or new features | All 3 passes | Full review with adversarial |

**Always run all 3 passes for:**
- Changes touching codegen AND runtime (contract risk)
- New language features (parser + codegen + runtime)
- Changes the user explicitly asks for deep review on
- **Any change touching these security-sensitive components:**

| Component | Files | Risk |
|-----------|-------|------|
| **REPL server** | `beamtalk_repl_server.erl`, `beamtalk_repl.erl` | TCP listener, accepts connections, spawns per-client processes |
| **REPL eval** | `beamtalk_repl_eval.erl` | Compiles & executes user code, file I/O |
| **Workspace persistence** | `beamtalk_workspace_meta.erl` | Reads/writes files from user paths |
| **Atom creation** | `beamtalk_object_class.erl`, `beamtalk_repl_eval.erl` | `list_to_atom` from user input (DoS risk) |
| **File path handling** | `beamtalk_repl_eval.erl`, CLI file loading | Path traversal, unsanitized user paths |
| **Process spawning** | `beamtalk_actor.erl`, `beamtalk_repl.erl` | Resource exhaustion, unbounded process creation |

**The user can override:** `/review-code --deep` forces all 3 passes regardless of size.

---

## Pass 1: Diff Review (correctness, style, DDD)

The fast pass — read the diff line by line, catch surface issues.

### Steps

1. **Identify the base branch**:
   ```bash
   git fetch origin main
   git merge-base HEAD origin/main
   ```

2. **Get the diff and changed files**:
   ```bash
   git --no-pager diff --stat $(git merge-base HEAD origin/main)..HEAD
   git --no-pager diff $(git merge-base HEAD origin/main)..HEAD
   ```

3. **Review each changed file** against the Review Guidelines below.

4. **DDD compliance check**: For each new or renamed module/type/function:
   - Does the name match the ubiquitous language in `docs/beamtalk-ddd-model.md`?
   - Is the bounded context documented in the module header?
   - If a new domain concept is introduced, is it added to the DDD model doc?
   - Are dependency directions correct (core never imports cli/lsp)?

5. **Test coverage check**:
   - Are there new tests needed for these changes?
   - Can I write an E2E test? (check `tests/e2e/cases/*.bt`)
   - Are there edge cases not tested?
   - Did existing tests need updating?

6. **Implement fixes**: For anything that can be done in <2 hours:
   - Fix bugs, edge cases, security issues
   - Add missing tests
   - Improve naming, docs, DDD alignment
   - Update `docs/beamtalk-ddd-model.md` for new domain concepts

7. **Verify CI passes** after any changes:
   ```bash
   just ci
   ```

8. **Pass 1 summary**: Report findings using the severity levels (🔴🟡🔵✅).

---

## Pass 2: System Review (cross-repo impact, algorithms, edge cases)

Zoom out from the diff. Think about how these changes interact with the rest of the system.

### Steps

9. **Read surrounding code**: For each changed file, read the **unchanged** code around it. Understand the full module, not just the diff:
   ```bash
   # For each significantly changed file, read the whole thing
   cat <file>
   ```

10. **Cross-component analysis**: Trace the data flow across component boundaries:
    - **Parser → Codegen**: Does the parser produce AST that codegen correctly consumes? Are all new AST variants handled in codegen match arms?
    - **Codegen → Runtime**: Does generated Core Erlang call runtime functions that exist with the right arity? Do state shapes match expectations?
    - **Runtime → REPL**: Do runtime changes appear correctly in REPL output? Are error messages formatted for users?
    - **Semantic → LSP**: Do new semantic analysis features feed into LSP completions/diagnostics?

11. **Edge case analysis**: For each algorithm or logic change, systematically check:
    - **Empty/nil**: What happens with empty collections, nil values, missing keys?
    - **Boundaries**: Integer overflow, atom exhaustion, process limits, string encoding?
    - **Concurrency**: Race conditions between actors? Message ordering assumptions?
    - **Error cascades**: If this fails, does the caller handle it? Does the error reach the user with a helpful message?
    - **State machines**: Are all transitions covered? Can you get stuck in a state?
    - **Reentrancy**: Can this function be called recursively? From a callback? During init?

12. **Contract verification**: Check that implicit contracts between layers are maintained:
    - Generated Core Erlang function signatures match what runtime expects
    - Error records use `#beamtalk_error{}` consistently across codegen and runtime
    - State variable naming conventions are consistent (`State0`, `State1`, etc.)
    - Module naming in codegen matches what runtime resolves

13. **Documentation cross-reference**: Check if changes require updates to:
    - `docs/beamtalk-language-features.md` — language syntax changes
    - `docs/beamtalk-architecture.md` — system design changes
    - `docs/beamtalk-ddd-model.md` — domain model changes
    - `examples/*.bt` — new features need examples
    - `AGENTS.md` — workflow or convention changes

14. **Implement fixes** from Pass 2 findings, re-run CI if changes made.

---

## Pass 3: Adversarial Review (CodeRabbit + challenge assumptions)

Use CodeRabbit AI and a different model family to challenge the design with fresh eyes.

### Steps

15. **Run CodeRabbit review** (if the `coderabbit:review` plugin is installed):

    Invoke the `/coderabbit:review` skill with `committed --base main`:
    ```
    /coderabbit:review committed --base main
    ```

    This runs the CodeRabbit CLI locally against committed changes and produces findings grouped by severity.

16. **Launch adversarial model review** using the task tool with a model from a **different family** than your own. If you're Claude, use GPT; if you're GPT, use Claude:

    Launch via `task` with `agent_type: "general-purpose"` and `model: "gpt-5.2-codex"` (or `model: "claude-opus-4.6"` if you're a GPT model):

    ```
    You are a skeptical senior engineer reviewing a PR. Your job is to find
    issues the original reviewer missed. Be adversarial but constructive.

    Review this diff: <paste diff or key files>

    Focus on:
    1. ASSUMPTIONS: What assumptions is this code making that might not hold?
    2. FUTURE FRAGILITY: What would break this in 6 months?
    3. SCALING: If this codebase 10x'd, would this approach still work?
    4. MISUSE: How could a user or developer misuse this?
    5. TESTING GAPS: What scenarios aren't tested?

    DO NOT comment on: style, formatting, naming conventions, or anything cosmetic.
    ONLY flag issues that could cause bugs, data loss, or significant maintenance burden.
    ```

17. **REPL verification** (for user-facing changes only — skip for infra-only):
    - Start REPL: `beamtalk repl`
    - Load relevant fixtures: `:load examples/counter.bt`
    - Test the specific changes interactively
    - Verify error messages are helpful and actionable
    - Document the REPL session in the summary

18. **Triage findings** from CodeRabbit and the adversarial review. For each:
    - **Valid and fixable now** → implement the fix
    - **Security issue, can't fix now** → create Linear issue with `Bug` label + urgent priority. **Never drop security findings.**
    - **Valid but out of scope** → create Linear issue
    - **Theoretical, unlikely in practice** → note but don't act
    - **Wrong / already handled** → dismiss with explanation

19. **Final CI run** if any changes were made in Pass 3:
    ```bash
    just ci
    ```

---

## Summary

20. **Create follow-up issues**: Anything found during review that isn't fixed in this PR **must** get a Linear issue — findings should never be just "noted" and forgotten.

    **Always create an issue for:**
    - 🔴 **Security findings not fixed now** — label `Bug` + `urgent priority`. Never let security issues be silently dropped.
    - 🟡 **Valid concerns deferred** — out-of-scope improvements, performance concerns with evidence, architectural suggestions
    - 🔵 **Adversarial/CodeRabbit findings worth tracking** — assumptions that could break, scaling concerns, missing test scenarios

    **Don't create issues for:**
    - Theoretical concerns with no plausible trigger
    - Things already handled that the adversarial reviewer missed

    **The bar for "fix it now" is still high** — prefer implementing over deferring. But if you defer, track it.

21. **Final summary**:

```markdown
## Code Review Summary

### Pass 1: Diff Review
- [x] Fixed: [description] (file:line)
- [x] Added: [tests/docs] for [feature]
- ✅ DDD compliance: [status]

### Pass 2: System Review
- [x] Fixed: [cross-component issue]
- [x] Verified: [contract between X and Y]
- ✅ Documentation: [updated/already current]

### Pass 3: Adversarial Review
- [x] Fixed: [assumption that was wrong]
- ⚠️ Noted: [theoretical concern, not acting]
- ✅ REPL verified: [what was tested]

### Issues Created
- 🔴 BT-XXX: [security finding — urgent]
- BT-YYY: [deferred improvement]
- BT-XXX: [only for substantial architectural work]

### Assessment
- **Ready to merge:** Yes/No
- **Strengths:** [key positive aspects]
- **Remaining concerns:** [any blocking issues]
```

---

## Review Guidelines

### Action Decision Matrix

- **Fix now** (<2 hours): bugs, security, missing tests/docs, edge cases, naming, style
- **Create Linear issue**: architectural changes, scope-expanding features, cross-team coordination, >2x PR size
- **Security findings are NEVER optional.** Can't fix now → Linear issue with `Bug` + urgent priority immediately.
- **When in doubt, implement it.**

### Coding Standards

Follow `CLAUDE.md` Essential Rules, `docs/agents/expanded.md`, and `docs/development/architecture-principles.md`. Key checks:
- DDD compliance: domain terms, bounded context headers, dependency direction (`docs/beamtalk-ddd-model.md`)
- Erlang: `#beamtalk_error{}` records, OTP logger, `-spec` declarations, license headers
- Rust: clippy `-D warnings`, no `unwrap()` on user input, `Document`/`docvec!` for codegen
- Beamtalk: verify syntax in codebase before using, implicit returns, `::` annotations

---

## Severity Levels

1. **🔴 Critical** — Fix immediately: bugs, crashes, security, logic errors
2. **🟡 Recommended** — Implement if straightforward: missing tests, unclear names, docs
3. **🔵 Larger** — Create Linear issue: architectural changes, major refactoring
4. **✅ Strengths** — Note what's done well: good coverage, clear code, proper error handling
