# 🧰 Solve4x Skills

**Little recipes that make AI agents less forgetful.**

Every time you explain a task to an agent, you're writing instructions it will forget tomorrow. A *skill* fixes that: a short, plain-English playbook the agent loads on demand and follows the same careful way every time.

These are the skills from [Solve4x](https://solve4x.ai) that are generic enough to share. Grab what's useful, remix the rest.

## ⚡ Quick start

```bash
git clone https://github.com/solve4x-hq/skills-public.git
```

Then link the skills into every AI coding tool you use, in one go (Windows PowerShell, no admin needed):

```powershell
.\tools\sync-skills.ps1 -Sources .\skills -Pull -Schedule
```

That links each skill into the folders Claude Code, Cursor, Codex, Devin and Grok read, so you edit a skill once (here, in git) and every tool sees it. `-Schedule` keeps them pulled and linked at sign-in and every few hours. Add your own skills repo to `-Sources`, and your project folders to `-Projects`.

| Tool | Reads skills from |
|---|---|
| Cursor | `~/.agents/skills`, `~/.cursor/skills`, and `.agents/skills` in a repo |
| Codex | `~/.agents/skills`, and `.agents/skills` in a repo |
| Devin | `%APPDATA%\devin\skills`, `~/.codeium/windsurf/skills`, and `.agents/skills` in a repo |
| Claude Code | `~/.claude/skills`, and `.claude/skills` in a repo |
| Grok | `~/.claude/skills`, `~/.grok/skills`, and paths in its `config.toml` |

Then type `/` in your agent's chat, pick a skill, and tell it what you need:

```
/skill-template help me write a skill for resetting a user's MFA
```

Not on Windows? Symlink the folders under `skills/` into the folders in the table.

## 📚 What's inside

| Skill | Reach for it when... |
|---|---|
| [`skill-authoring`](./skills/skill-authoring/SKILL.md) | you're creating, moving, or publishing a skill and want it in the right place, marked private or public. |
| [`skill-template`](./skills/skill-template/SKILL.md) | you're writing a new skill and want a solid starting shape. |
| [`agents-md`](./skills/agents-md/SKILL.md) | you're starting or updating a repo's AGENTS.md, or a rule for every repo changed. |
| [`root-cause`](./skills/root-cause/SKILL.md) | you're fixing a bug or anything that "shouldn't happen", before writing the fix. |
| [`plain-words`](./skills/plain-words/SKILL.md) | you're writing UI text, errors or reports for non-technical people. |
| [`ui-check`](./skills/ui-check/SKILL.md) | a change touches anything a person sees, before calling it done. |
| [`handoff`](./skills/handoff/SKILL.md) | you're handing work to another AI agent or a person. |
| [`new-repo`](./skills/new-repo/SKILL.md) | you want a new GitHub repository: it asks a few plain questions, then sets everything up. |

More are on the way as they get cleaned up for public use.

## ✍️ Write your own

1. Copy `skills/skill-template/` to `skills/<your-skill-name>/`.
2. Write a `description` that says **when** to use it. That's how the agent decides to pick it up.
3. Keep the steps short, numbered, and checkable.
4. Put the "never do this" rules at the bottom, where they're hard to miss.
5. Check it before committing: `.\tools\check-skills.ps1 -Root . -Expect public`. Turn on the pre-commit hook once with `git config core.hooksPath .githooks` and it runs on every commit.

> **Rule of thumb:** if you've explained it to an agent twice, it's a skill.

## 🔒 House rules

No secrets, keys, IPs, client names, or personal info. Skills say *where* to find things, never *what* they are. The checker enforces it, and refuses any word in your own private denylist (`~/.config/skills-denylist.txt`, kept outside the repo).

## 🛠️ Tools

- [`tools/sync-skills.ps1`](./tools/sync-skills.ps1): links your skills repos into every AI tool's skills folder and keeps them pulled.
- [`tools/check-skills.ps1`](./tools/check-skills.ps1): checks each skill's shape and privacy marking, and scans for leaks.
- [`tools/new-repo/new-repo.ps1`](./tools/new-repo/new-repo.ps1): creates a complete repo (docs, security files, templates, GitHub settings) from the `new-repo` skill's answers.

## 🤝 Contributing

Found a bug or have an improvement? Open an issue or a PR. Small and practical beats big and clever.

## 📄 License

[MIT](./LICENSE): use, change and share freely.

---

Built by [Solve4x](https://solve4x.ai) 🌲
