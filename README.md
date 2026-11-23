# My Nix setup (Sécurix / NixOS)

## The big picture

This machine has **two layers**:

| Layer | Who controls it | Where | What you do |
|---|---|---|---|
| **System** (kernel, KDE, security, `/etc`) | DINUM / IT (Sécurix Bureautix) | not on this machine | nothing; no `sudo`, by design |
| **User** (your apps, shell, git, dotfiles) | **you** | this folder | edit `home.nix`, run `hms` |

### Core ideas

1. **Everything lives in `/nix/store`**, in paths like `/nix/store/<hash>-ripgrep-15.2.0`.
   Packages never overwrite each other, so several versions can coexist.
2. **Declarative:** you describe *what you want* in a file. You don't run `apt install`.
   Nix builds that state, and you can rebuild it on any machine from the same files.
3. **Generations:** every switch creates a new generation, and you can always roll back.
4. **Flakes:** `flake.nix` declares inputs and `flake.lock` pins their exact versions.
   Same lock = same result. Nix only sees files that are **tracked by git**, so `git add` new files!
5. **Store files are read-only and world-readable.** That's why `~/.zshrc` is now a
   symlink into the store, and why secrets stay outside Nix (`~/.config/secrets/env`).

## Files

- `flake.nix`: inputs (nixpkgs 26.05, nixpkgs-unstable, home-manager, agent-vm)
- `home.nix`: **the file you edit**: packages, zsh, git, direnv, starship
- `flake.lock`: pinned versions (auto-generated, commit it)
- `~/.config/secrets/env` (outside this repo, mode 600): API keys, sourced by zsh

## Daily commands

| Goal | Command |
|---|---|
| Apply changes to `home.nix` | `hms` |
| Try a tool once, without installing it | `nix shell nixpkgs#cowsay` → `cowsay hi` |
| Run a tool directly | `nix run nixpkgs#cowsay -- hi` |
| Search packages | `nix search nixpkgs ripgrep` or https://search.nixos.org |
| Find options (zsh, git...) | https://home-manager-options.extranix.com |
| Update all inputs (new versions) | `nix flake update` then `hms` |
| List generations | `home-manager generations` |
| Roll back | `home-manager generations` → run `<path>/activate` of the previous one |
| Free disk space (old generations) | `home-manager expire-generations "-30 days"` then `nix store gc` |
| Why is X installed? | `nix-tree` |

### Installing something permanently

Add it to `home.packages` in `home.nix`, then `hms`. Commit the change:

```sh
git add -A && git commit -m "add foo"
```

Avoid `nix profile install` / `nix-env -i`. Those are imperative installs that
your config doesn't track (and they conflict with Home Manager).

### Per-project dev environments

For a project that needs specific tools (node, python, go...), give it its own `flake.nix` with a
`devShells.default`, plus a `.envrc` containing `use flake`, then run `direnv allow` once.
The tools then load automatically whenever you `cd` into the project.
(`~/nix/sites-conformes-dev` is already shaped this way.)

## Nix language in 60 seconds

```nix
{ a = 1; b = "text"; }            # attribute set (like a JSON object)
[ pkgs.git pkgs.jq ]              # list (space separated, no commas!)
x: x + 1                          # function taking x
{ pkgs, ... }: { ... }            # function taking a set (that's what home.nix is)
let y = 2; in y * 3               # local variables
"hello ${name}"                   # interpolation
''multi-line string''             # indented string (used for shell snippets)
programs.git.enable = true;       # shorthand for { programs = { git = { enable = true; }; }; }
```

## Git signing with the YubiKey

- Signing key: `~/.ssh/id_ed25519_sk` (a FIDO2 handle, useless without the YubiKey).
  Its public half is in `keys/` and generates `~/.config/git/allowed_signers`.
- GitHub push/pull: `~/.ssh/id_ed25519_sk_rk_github` (see `programs.ssh` in `home.nix`).
- Every `git commit` / `git tag` blinks the key: **touch it**.
- Check: `git verify` (alias) → `G` = good signature, `N` = unsigned.
- Debug: `fido2-token -L` (is the key seen?), `ykman info`.
- New machine: `ssh-keygen -K` re-downloads only *resident* keys (the `_rk` GitHub one).
  The signing key is **not** resident, so keep a backup of `~/.ssh/id_ed25519_sk`
  (useless without the YubiKey). If it's lost, generate a new signing key with
  `ssh-keygen -t ed25519-sk -O application=ssh:git-sign` and update `keys/`.
- GitHub shows "Verified" only if the public key is added as a **Signing key**
  in https://github.com/settings/keys (separately from the authentication key).

## agent-vm + Albert

- `agent-vm` comes from the flake input; `albert-code` is a git clone in `~/albert-code`
  (shim in `~/.local/bin`), and it vendors the same agent-vm version.
- The Albert key: `~/.config/secrets/env` (host shell) and `~/.agent-vm/runtime.sh`
  (pushed into each VM). Both are mode 600 and outside this repo.
- `ZSHENV` points albert-code at the secrets file, since `~/.zshenv` is read-only now.
- Per project: `cd project && albert-code setup`, then `albert-code run`.
  Or plain agents: `agent-vm claude`, `agent-vm opencode`.
- Health check: `agent-vm doctor`. Rebuild the base VM: `agent-vm setup`.
- Rotate the Albert key: edit both files above, then restart the VMs (`agent-vm stop`).

## Shell history

`home.nix` makes zsh skip duplicates and never save commands containing
`API_KEY=`, `TOKEN=`, `sk-eyJ` or `github_pat_`. Start a command with a space
to keep it out of history.

## Unfree packages

`claude-code` is unfree. `config.allowUnfree = true` in `flake.nix` replaces the old
`NIXPKGS_ALLOW_UNFREE=1 ... --impure` workaround.
