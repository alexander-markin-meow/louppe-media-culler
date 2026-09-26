# Engineering guidance review — 2026-09-26

Reviewed public repositories belonging to [Kirill Markin](https://github.com/kirill-markin)
and [Andrey Markin](https://github.com/Mark-Life). This is a source record and
rationale; `AGENTS.md` owns the adopted instructions.

## Selection and scope

GitHub's public API supplied star counts, archive status, last-push dates, and
complete recursive file trees. Prioritized recently updated, non-fork,
non-archived projects with more stars. Stars are a discovery signal, not proof
of engineering quality. Andrey's public repositories have comparatively few
stars, so recent activity and relevant guidance also informed selection.
Last push does not necessarily mean a recent substantive code change.

Searched the selected trees for `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, Cursor
rules, Claude rules, and Copilot instructions; read the discovered instruction
files, resolving aliases and deduplicating identical contents. Also followed
the relevant native-app and code-quality references. This was a guidance review,
not an audit of every implementation or every repository on either account.

| Repository | Stars | Last push | Guidance inspected |
| --- | ---: | --- | --- |
| [Kirill: repo-to-text][repo-text] | 211 | 2026-08-12 | `AGENTS.md` and `CLAUDE.md` point to `.cursor/rules/index.mdc` |
| [Kirill: flashcards-open-source-app][flashcards] | 73 | 2026-09-26 | `AGENTS.md`, `CLAUDE.md` alias, and `apps/ios/README.md` |
| [Kirill: meta-glasses-ios-openai][glasses] | 62 | 2026-01-15 | `CLAUDE.md`; older, included for SwiftUI relevance |
| [Kirill: chatgpt-telegram-bot-telegraf][kirill-bot] | 43 | 2026-09-16 | `.cursorrules` |
| [Kirill: example-mcp-server][mcp-example] | 38 | 2026-08-15 | No matching agent instruction files found |
| [Kirill: expense-budget-tracker][expenses] | 32 | 2026-09-25 | `AGENTS.md` and `CLAUDE.md` alias |
| [Andrey: telegram-claude-codex][andrey-bot] | 9 | 2026-09-22 | `AGENTS.md` alias and `CLAUDE.md` |
| [Andrey: ai-form][ai-form] | 4 | 2025-12-06 | Cursor Ultracite rules; older comparison |
| [Andrey: peektrace][peektrace] | 2 | 2026-09-26 | `AGENTS.md` alias, `CLAUDE.md`, referenced `quality-code` skill |
| [Andrey: agent-skills][agent-skills] | 2 | 2026-09-25 | No root agent rules; read `human-to-agent` and `product` skills as reference material |
| [Andrey: recruit-ai][recruit] | 0 | 2026-04-01 | `AGENTS.md` alias, `CLAUDE.md`, Cursor Ultracite rules; architecture comparison |

Kirill's `chrome-auto-image-blocker` had 82 stars but no push since 2025-03-07;
it was omitted from the deeper review in favor of more current guidance.
Counts and dates above are a snapshot, not values to maintain in agent context.

## What transfers to Louppe

| Source | Useful practice | Louppe adaptation |
| --- | --- | --- |
| [Kirill's native iOS guide][ios-guide] | Read neighboring implementations, reuse helpers, prefer native controls and platform APIs | SwiftUI/AppKit conventions, preserving Louppe's necessary AppKit bridges and SwiftPM build |
| [Kirill's flashcards rules][flashcards] | Simple, scoped changes; pure domain functions; immediate action feedback; actionable errors | Shared domain logic and immediate UI feedback, with durable success tied to real worker outcomes |
| [Andrey's quality-code skill][quality] | Typed identities and mutually exclusive states; shared types; realistic tests | Swift enums, existing identity/plan types, labeled arguments, disposable-file integration checks |
| [Kirill's expense rules][expenses] and [Andrey's quality-code skill][quality] | Explicit failures and structured diagnostics | Existing Apple logging and signposts; preserve Louppe's intentional recovery and preview fallbacks |
| [Andrey's Peektrace instructions][peektrace] | Consult dependency sources matching the version in use | Check selected SDK and pinned package sources before guessing APIs |
| [Andrey's instruction-writing skill][human-agent] | Concrete rules, one canonical location, observable completion criteria, linked detail | Maintain existing rules in place and report actual verification results |

The Swift-specific details, filesystem revalidation, privacy constraints, and
durability qualifications are local adaptations, not claims that their source
documents already specify Louppe's behavior.

## What was deliberately left out

- Web/backend tooling and architecture: React, Next.js, Bun, Effect.ts,
  PostgreSQL, cloud deployment, API discovery, auth, and server-owned domain logic.
- Copying iOS navigation, simulator, Xcode-project, or mobile release procedures
  into a native macOS SwiftPM app.
- Kirill's blanket restrictions on adding unit tests and using classes, and a
  blanket ban on fallback logic. Louppe needs its regression tests, observable
  store, AppKit objects, backup persistence, and preview fallbacks.
- Andrey's specific OpenTelemetry tooling. The useful principle is diagnostic
  evidence; Louppe already has native logging and performance signposts.
- Automatic push/deploy/merge policies, different versioning rules, or relaxed
  test gates. Louppe's existing owner authorization and release rules remain.
- Framework replacement, agent-first product expansion, and autonomous actions
  from broader product guidance. They do not serve this requested rules update.
- Repeating protections already documented for state ownership, cancellation,
  schema compatibility, journaling, and physical-file identity.

Only documentation changed. The latest published release was `v1.8.0`; the
existing `1.9.0 (11)` development cycle was already open, so no version bump
was needed.

## Follow-up: instruction length

The first update left `AGENTS.md` at 4,159 words / 440 lines. For comparison,
the inspected Flashcards `AGENTS.md` had 2,111 words and Telegram Claude Codex's
effective instructions in `CLAUDE.md` had 2,083 words; both also use supporting
references. Those are comparisons, not a universal size limit.

At the owner's request, condensed the new engineering advice and moved the
architecture map and subsystem details into [DEVELOPMENT_DETAILS.md](DEVELOPMENT_DETAILS.md).
The root now has 1,732 words / 216 lines, with explicit task-based links.
All previous safety/gotcha requirements and build, test, and repository rules
remain available. Corrected the count of sanctioned exceptions from three to
four to match the existing list. This follows [OpenAI's guidance on keeping
agent instructions relevant to the task](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra#up-to-date-agentsmd).

[repo-text]: https://github.com/kirill-markin/repo-to-text/blob/9a397eb6ee6d06f1e6647a542acc32a78c4b8fb7/.cursor/rules/index.mdc
[flashcards]: https://github.com/kirill-markin/flashcards-open-source-app/blob/cafb497df760e0b4aae2f5ea4d553726f2fe0dac/AGENTS.md
[ios-guide]: https://github.com/kirill-markin/flashcards-open-source-app/blob/cafb497df760e0b4aae2f5ea4d553726f2fe0dac/apps/ios/README.md
[glasses]: https://github.com/kirill-markin/meta-glasses-ios-openai/blob/fd998ee3b8248fae11c099c8e91ee6be53f7212d/CLAUDE.md
[kirill-bot]: https://github.com/kirill-markin/chatgpt-telegram-bot-telegraf/blob/0a2b5f1481b9212f90642099e05bf55184bf4cf4/.cursorrules
[mcp-example]: https://github.com/kirill-markin/example-mcp-server/tree/1f8266016aa82a765b2a64fbffd6d88c53b5072a
[expenses]: https://github.com/kirill-markin/expense-budget-tracker/blob/5f9666af5c1a27fcc7f76be97b40e0c21f7d5405/AGENTS.md
[andrey-bot]: https://github.com/Mark-Life/telegram-claude-codex/blob/08897b6a7803c9a3189d88b9d0bd43ca92feedc8/CLAUDE.md
[ai-form]: https://github.com/Mark-Life/ai-form/blob/936a7eb0d5df7228ae8e25303edf3e779cc5637a/.cursor/rules/ultracite.mdc
[peektrace]: https://github.com/Mark-Life/peektrace/blob/b0d39b0ba2e891eb8504c1e2684af0df2e9af427/CLAUDE.md
[quality]: https://github.com/Mark-Life/peektrace/blob/b0d39b0ba2e891eb8504c1e2684af0df2e9af427/.agents/skills/quality-code/SKILL.md
[agent-skills]: https://github.com/Mark-Life/agent-skills/tree/439b2114d6d8e94bee641b556206b0597c56a9a8
[human-agent]: https://github.com/Mark-Life/agent-skills/blob/439b2114d6d8e94bee641b556206b0597c56a9a8/skills/communication/human-to-agent/SKILL.md
[recruit]: https://github.com/Mark-Life/recruit-ai/blob/87a5d868fcd489ee1a22bb77f9e89abd33be40a1/CLAUDE.md
