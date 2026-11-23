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

## How this folder is hooked to the system

**It isn't, permanently.** Nothing on the machine points back to this folder.
It is only read when you run `hms`, which *builds* a snapshot and then *switches* your
home over to it. Delete or move the folder and your environment keeps working;
you just can't change it until you point `hms` at the new location.

```
 dotfiles/     (flake.nix, home.nix, flake.lock)
      │
      │  hms = home-manager switch --flake ~/Documents/projets/dotfiles#jbouquillon
      │        1. evaluate  → reads homeConfigurations.jbouquillon from flake.nix
      │        2. build     → everything lands in /nix/store (read-only)
      │        3. activate  → updates the symlinks below
      ▼
 /nix/store/…-home-manager-generation      ← one complete, self-contained snapshot
      ├── home-path/   all your packages (bin/, share/…)
      ├── home-files/  generated dotfiles (.zshrc, git config, ssh config…)
      └── activate     the script that does step 3
```

**What `activate` links into your home:**

| Link in your home | Points to | Effect |
|---|---|---|
| `~/.local/state/nix/profiles/home-manager` | current generation (`home-manager-N-link`) | the list of generations you can roll back to |
| `~/.nix-profile` → `profiles/profile` | a profile containing `home-manager-path` | `~/.nix-profile/bin` is on your `PATH` (set by NixOS), so packages show up |
| `~/.zshrc`, `~/.zshenv`, `~/.ssh/config`, `~/.config/git/config`, `~/.config/git/allowed_signers` | files inside `…-home-manager-files/` | your dotfiles, read-only |
| `~/.zshenv` sources `hm-session-vars.sh` | store | `EDITOR`, `ZSHENV`, `~/.local/bin` on `PATH` |
| `~/.local/state/home-manager/gcroots/current-home` | current generation | tells `nix store gc` not to delete it |

**Where you sit relative to the system layer:**

```
 /run/current-system   ← Sécurix (DINUM). Kernel, KDE, sshd, yubikey-agent, starship, git…
        ▲                PATH: /run/current-system/sw/bin
        │ provides nix, PATH setup, /etc/zshrc
 ~/.nix-profile        ← YOU (this folder, via hms)
                         PATH: ~/.nix-profile/bin, which comes before the system one
```

So you can install your own version of a tool that the system also ships,
and yours wins in your shell. You can't change system services, users or `/etc`.

**Things that follow from this:**
- Editing `home.nix` changes nothing until you run `hms`.
- Never edit `~/.zshrc` and friends directly: they're read-only symlinks, and the next `hms` replaces them anyway.
- Rollback = re-activating an older generation: `home-manager generations`, then
  run `/nix/store/…-home-manager-generation/activate` for the one you want.
- Old generations are kept (and use disk space) until you expire them and run `nix store gc`.
- On a new machine: see [Reproduce on a new Bureautix computer](#reproduce-on-a-new-bureautix-computer).

## Reproduce on a new Bureautix computer

Starting point: a fresh Sécurix/Bureautix machine where you can log in (IT has
enrolled your YubiKey), with your YubiKey and access to the old machine or your backups.

### 0. What's not in this repo (gather first)

| File | Why it's not in git | How to get it on the new machine |
|---|---|---|
| `~/.ssh/id_ed25519_sk` (+ `.pub`) | commit-signing key handle, **not** resident on the YubiKey | copy from the old machine / your backup |
| `~/.ssh/id_ed25519_sk_rk_github` (+ `.pub`) | GitHub auth key handle | resident: re-download from the YubiKey (step 2) |
| `~/.config/secrets/env` | Albert API key for your shell | copy, or recreate (step 5) |
| `~/.agent-vm/runtime.sh` | pushes the Albert key into the VMs | copy from the old machine (step 6) |

Copy files with a USB stick or `scp`, never through a git repo. Their permissions must be `600`.

### 1. Enable flakes

Flakes are off by default in Nix:

```sh
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

### 2. Get your SSH keys

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh && cd ~/.ssh
ssh-keygen -K          # touch the YubiKey (+ FIDO PIN if asked) → writes id_ed25519_sk_rk_github{,.pub}
# + copy id_ed25519_sk and id_ed25519_sk.pub from your backup here
chmod 600 ~/.ssh/id_ed25519_sk*; chmod 644 ~/.ssh/*.pub
```

### 3. Clone this repo

`~/.ssh/config` doesn't exist yet, so name the key explicitly. Keep this exact path,
because the `hms` alias points to it.

```sh
mkdir -p ~/Documents/projets
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_sk_rk_github" \
  git clone git@github.com:revolunet/dotfiles.git ~/Documents/projets/dotfiles
```

If your username isn't `jbouquillon`, change `home.username`, `home.homeDirectory`
and `homeConfigurations.jbouquillon` (in `flake.nix`) first.

### 4. First switch

```sh
cd ~/Documents/projets/dotfiles
[ -f ~/.gitconfig ] && mv ~/.gitconfig ~/.gitconfig.backup   # would override Home Manager's git config
nix profile list   # if it lists packages you installed by hand, `nix profile remove <name>` them (they'd conflict)
nix run github:nix-community/home-manager/release-26.05 -- switch --flake .#jbouquillon -b backup
```

`-b backup` renames existing dotfiles (`~/.zshrc` → `~/.zshrc.backup`) instead of failing.
Then **open a new terminal**: you get zsh with starship, all packages, the `hms` alias,
and `home-manager` itself. From now on, use `hms`.

### 5. Secrets

If you didn't copy `~/.config/secrets/env`, create it (the leading space keeps the command
out of history):

```sh
mkdir -p ~/.config/secrets && chmod 700 ~/.config/secrets
 echo "export ALBERT_API_KEY='sk-…'" > ~/.config/secrets/env   # note the leading space
chmod 600 ~/.config/secrets/env
```

### 6. agent-vm + Albert

```sh
git clone https://github.com/etalab-ia/albert-code.git ~/albert-code   # the wrapper in home.nix expects this path
mkdir -p ~/.agent-vm
# copy ~/.agent-vm/runtime.sh from the old machine, then:
chmod 600 ~/.agent-vm/runtime.sh
agent-vm setup --cpus 4 --memory 8 --disk 32 \
  --preinstall=node,python,gh,chromium,docker,opencode,claude,mcp-chrome   # ~10 min
agent-vm doctor     # expect: "No problems found"
```

**Don't** run `albert-code install`. It sets up its own old VM engine, and the wrapper refuses to run it anyway.
Per project: `albert-code setup`, then `albert-code run`.

### 7. Check everything

```sh
cd "$(mktemp -d)" && git init -q                 # throwaway repo
git commit --allow-empty -m "test signing"       # YubiKey blinks: touch it
git verify                                       # first column G = good signature
cd ~
ssh -T git@github.com                        # touch: "Hi <user>! You've successfully authenticated"
echo ${ALBERT_API_KEY:+albert key loaded}
agent-vm doctor
```

GitHub already knows both public keys (same YubiKey), so pushing and the
"Verified" badge work right away.

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

- `agent-vm` comes from the flake input (Lima built in, no `limactl` needed).
- `albert-code` is a git clone in `~/albert-code`, but its bundled agent-vm is an
  old version that clashes with the Nix one. So `albert-code` on your PATH is a
  wrapper from `home.nix`:
  - `albert-code run [--reset]` → `agent-vm run --tty zsh -l -c "opencode --auto"`
    (the same command, through the Nix agent-vm, with read-only `.git`)
  - `setup` / `update` → the real `~/albert-code/bin/albert-code`
  - `install` → not needed; use `agent-vm setup` / `agent-vm doctor`
- Don't install `lima` from nixpkgs: it would let the old bundled engine build its
  own VMs in `~/.lima` without the `.git` protection.
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
