# dotfiles — my Nix user environment (Sécurix / NixOS)

Your machine has two layers:

| Layer | Who controls it | Where | Your workflow |
|---|---|---|---|
| **System** (kernel, KDE, security, `/etc`) | DINUM / IT | elsewhere | nothing; no `sudo`, by design |
| **User** (apps, shell, git, dotfiles) | **you** | this folder | edit `home.nix`, run `hms` |

This repo is the *recipe* for your user layer. `hms` turns it into a snapshot in
`/nix/store` and links your home to it. Nothing else re-runs at boot — the links
are ordinary files and the snapshot is pinned against garbage collection.

## Files

- `flake.nix` — inputs (nixpkgs 26.05, nixpkgs-unstable, home-manager, agent-vm) + outputs
- `home.nix` — **the file you edit**: packages, zsh, git, direnv, starship
- `flake.lock` — pinned versions (auto-generated, commit it)
- `~/.config/secrets/env` — API keys (outside this repo, mode 600, sourced by zsh)

Keep it simple: edit `home.nix`, run `hms`. Rollback and history live in generations
(`home-manager generations`), tweaks you don't commit are lost.

## Daily commands

| Goal | Command |
|---|---|
| Apply changes to `home.nix` | `hms` |
| Try a tool once | `nix shell nixpkgs#cowsay` |
| Search packages | `nix search nixpkgs ripgrep` or https://search.nixos.org |
| Find home-manager options | https://home-manager-options.extranix.com |
| Update everything | `nix flake update` then `hms` |
| Roll back | `home-manager generations` → run `<path>/activate` of an older one |
| Free disk space | `home-manager expire-generations "-30 days"` then `nix store gc` |
| Why is X installed? | `nix-tree` |

## Adding a package

1. Add it to `home.packages` in `home.nix` (prefix `pkgs.` for stable,
   `unstable.` for fast-moving tools).
2. `hms`, then commit.

Avoid `nix profile install` / `nix-env -i`: those installs aren't tracked by
this config and conflict with Home Manager.

## Markdown preview in Dolphin

`md-preview.nix` gives a styled preview of `.md` files in Dolphin:
**middle-click** opens the styled HTML in the default browser (Firefox),
**Shift+middle-click** opens the styled PDF, **right-click** adds
*Markdown Preview (Browser / PDF)* to the menu.
The PDF route is Chromium-only upstream (`md-preview`'s `_find_chromium`), so
the middle-click default uses the browser route, which works with Firefox.
Mermaid diagrams and KaTeX math work offline: the browser bundles are
vendored via Nix (pinned, served from the store). Adds `assets` at build time,
so the first `hms` needs HTTPS access to `github.com`, `registry.npmjs.org`
(katex 0.16.11, mermaid 11.17.2 — MIT). Double-click on `.md` stays on Kate
(the default is set in `xdg.mimeApps.defaultApplications`).

## Addons

Every addon in this setup, where it lives, and how to switch it off:

| Addon | What it does | Toggle | Where |
|---|---|---|---|
| **Markdown preview (Dolphin)** | Themed `.md` preview: middle-click → HTML in Firefox, Shift+middle-click → PDF (Chromium), right-click menu. | Remove `./md-preview.nix` from `imports` in `home.nix`, then `hms`. | `md-preview.nix` |
| **agent-vm + Albert** | Sovereign AI agent: `agent-vm` from its own flake input, `albert-code` wrapper routes `run` through the Nix agent-vm. | Flake input in `flake.nix`; `agent-vm` + `albertCode` in `home.packages`. Per project: `albert-code setup`. | `flake.nix`, `home.nix` |
| **YubiKey SSH signing** | Git commits/tags signed with a FIDO2 `sk-ed25519` key; pushes via the resident GitHub key. Each commit needs a key touch. | `programs.git.signing` + `programs.ssh` in `home.nix`; public half in `keys/`. | `home.nix`, `keys/` |
| **Secrets gate (gitleaks)** | Global pre-commit hook refuses any commit containing a secret, in every repo (via `core.hooksPath`). | `home.file` pre-commit hook + `gitleaks` in `home.packages`. Never bypass. | `home.nix` |
| **Shell (zsh + starship + direnv)** | Autosuggestions, syntax highlighting, secret-proof history, starship prompt, per-project `direnv`+`nix-direnv`. | `programs.zsh/starship/direnv` in `home.nix`. | `home.nix` |
| **Unfree packages** | Enables `claude-code` (and any other unfree package). | `config.allowUnfree = true` for both package sets. | `flake.nix` |

## Secrets & gitleaks

- Anything in `/nix/store` is world-readable, so secrets live outside Nix in
  `~/.config/secrets/env` (mode 600), sourced by zsh via `~/.zshenv`.
- **Every git commit runs `gitleaks protect --staged`** through a global
  pre-commit hook (`~/.config/git/hooks/`, enabled via `core.hooksPath`).
  A detected secret blocks the commit. Never bypass it (`git commit --no-verify` is forbidden).
- zsh never saves commands containing `API_KEY=`, `TOKEN=`, `sk-eyJ`, `github_pat_`.
  Start a command with a space to keep it out of history entirely.

## Git signing with the YubiKey

- Signing key: `~/.ssh/id_ed25519_sk` (a FIDO2 handle — useless without the key),
  public half committed in `keys/` for `allowed_signers`.
- Every commit/tag requires touching the key. Check with `git verify` (`G` = good).
- The `_rk_github` key is resident: re-download with `ssh-keygen -K` on a new machine.
  The signing key is **not**; keep a backup of `id_ed25519_sk`.
- GitHub shows "Verified" only if the public key is registered as a **Signing key**
  in https://github.com/settings/keys.

## agent-vm + Albert

- `agent-vm` comes from the flake (Lima built in). `albert-code` on the PATH is a
  wrapper that routes `run` through the Nix agent-vm (its bundled engine is old
  and must not be used — `albert-code install` is refused).
- Albert key lives in `~/.config/secrets/env` and `~/.agent-vm/runtime.sh` (both 600).
- Per project: `albert-code setup`, then `albert-code run`. Health: `agent-vm doctor`.

## Reproduce on a new Bureautix machine

1. **Enable flakes**: `echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf`
2. **SSH keys**: `ssh-keygen -K` in `~/.ssh` (re-downloads the resident GitHub key);
   copy `id_ed25519_sk` from your backup (not resident). `chmod 600 ~/.ssh/id_ed25519_sk*`.
3. **Clone** this repo to `~/Documents/projets/dotfiles` (the `hms` alias points there):
   `GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_sk_rk_github" git clone git@github.com:revolunet/dotfiles.git`
   If your username isn't `jbouquillon`, fix `home.username`, `home.homeDirectory` and
   `homeConfigurations.jbouquillon` first.
4. **First switch** (rename existing dotfiles instead of failing):
   `nix run github:nix-community/home-manager/release-26.05 -- switch --flake .#jbouquillon -b backup`.
   Open a new terminal, then use `hms` from now on.
5. **Secrets**: copy `~/.config/secrets/env` (create it if needed) and `~/.agent-vm/runtime.sh`.
6. **agent-vm**: clone albert-code to `~/albert-code`, then `agent-vm setup` + `agent-vm doctor`.

## Nix language in 60 seconds

```nix
{ a = 1; b = "text"; }            # attribute set (like JSON)
[ pkgs.git pkgs.jq ]              # list (space separated, no commas!)
{ pkgs, ... }: { ... }            # function taking a set (that's home.nix)
let y = 2; in y * 3               # local variables
"hello ${name}"                   # interpolation
''multi-line string''             # indented string (shell snippets)
programs.git.enable = true;       # shorthand for nested { programs = { git = … } }
```

Nix only sees files **tracked by git** — `git add` new files before `hms`.

## Unfree packages

`claude-code` is unfree; `config.allowUnfree = true` in `flake.nix` already handles it.
