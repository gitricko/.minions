# Wiki Index

This index maps all wiki articles in this directory. Each article is a reference document (how system Y works) distinct from skills (procedural how-to).

## Article List

| Article | Description | Related Skills |
|---------|-------------|----------------|
| [codespace-playbook.md](codespace-playbook.md) | Comprehensive Hermes + Codespace operations guide | github-codespace, codespace-gh-auth |
| [codespace-gh-auth.md](codespace-gh-auth.md) | GitHub token extraction from VS Code server | codespace-gh-auth, github-codespace |
| [codespace-lifecycle.md](codespace-lifecycle.md) | Codespace idle detection, shutdown, keepalive | github-codespace |
| [codespace-persistent-symlinks.md](codespace-persistent-symlinks.md) | Persisting Hermes state across rebuilds via symlinks | codespace-persistent-symlinks, mnemon-seed-persistence, persistent-knowledge |
| [codespace-port-visibility.md](codespace-port-visibility.md) | Automating port visibility via gh CLI | codespace-port-visibility, codespace-gh-auth |
| [codespace-webtop.md](codespace-webtop.md) | Selkies/XFCE webtop (browser desktop) | codespace-webtop |
| [docker-test-shell-proposal.md](docker-test-shell-proposal.md) | DTS design rationale | docker-test-shell |
| [github-actions-testing-plan.md](github-actions-testing-plan.md) | CI/CD testing plan | ci-lint-check, github-codespace |
| [github-codespace.md](github-codespace.md) | Full GitHub Codespace workflow (auth, CI, PR) | github-codespace, codespace-gh-auth |
| [github-pr-review.md](github-pr-review.md) | CodeQL/Copilot review evaluation | github-pr-review |
| [karpathy-coding-guidelines.md](karpathy-coding-guidelines.md) | LLM coding pitfall guidelines | karpathy-coding-guidelines |
| [keepalive-proposal.md](keepalive-proposal.md) | Keepalive design + A/B variants | github-codespace |
| [memory-automation.md](memory-automation.md) | Mnemon persistence workflow | memory-automation |
| [mnemon-graph-viewer.md](mnemon-graph-viewer.md) | 3D knowledge graph visualization | mnemon-graph-export |
| [mnemon-seed-persistence.md](mnemon-seed-persistence.md) | Seed.json management for contributors | mnemon-seed-persistence |
| [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) | Broader knowledge persistence architecture | persistent-knowledge |
| [persistent-knowledge.md](persistent-knowledge.md) | Persistent skills/knowledge via symlinks | persistent-knowledge |
| [persistent-memory-proposal.md](persistent-memory-proposal.md) | MEMORY.md/USER.md symlink architecture | codespace-persistent-symlinks |
| [repository-analysis.md](repository-analysis.md) | Repository deep dive | minions-architecture |
| [selkies-package-discrepancy.md](selkies-package-discrepancy.md) | PyPI vs GitHub Actions gotcha | codespace-webtop |
| [vscode-cli-codespaces.md](vscode-cli-codespaces.md) | VS Code CLI auto-discovery | codespace-vscode-open |

## How to Use

- **For agents**: Use `read_file()` to load any article by its path (e.g., `wiki/codespace-playbook.md`).
- **For humans**: Navigate via the table above. All links are relative to this directory.
- **Cross-references**: Articles link to each other via relative paths. Skills reference wiki via `../wiki/article.md`.
- **Adding new articles**: Add a row to this table AND ensure the filename matches the link.

*Last updated: 2026-09-12*
