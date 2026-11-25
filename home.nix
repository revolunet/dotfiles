# Your user environment, declared in one place.
# Edit this file, then run: hms   (alias for home-manager switch, see below)
# Option reference: https://home-manager-options.extranix.com
{ config, pkgs, unstable, agent-vm, ... }:

let
  gitEmail = "julien.bouquillon@numerique.gouv.fr";
  # Public half of the YubiKey signing key (safe to commit).
  signingPubKey = pkgs.lib.removeSuffix "\n" (builtins.readFile ./keys/id_ed25519_sk.pub);

  # albert-code (git clone in ~/albert-code) bundles an OLD copy of agent-vm
  # that clashes with the Nix one: it needs a separate `limactl`, keeps its VMs
  # in ~/.lima, lacks the read-only .git protection, and deletes the shared
  # ~/.agent-vm/.agent-vm-base-version marker. So `run` goes through the Nix
  # agent-vm (same command albert-code would run); setup/update don't use a VM
  # and go to the real albert-code unchanged.
  albertCode = pkgs.writeShellScriptBin "albert-code" ''
    real="$HOME/albert-code/bin/albert-code"
    # `albert-code run [agent-vm options]`, e.g. `albert-code run --reset`
    if [ "''${1:-}" = run ]; then
      shift
      if ! grep -qs '"albert"' ./opencode.json; then
        echo "This project isn't configured for Albert (no opencode.json with the albert provider)." >&2
        echo "Run: albert-code setup" >&2
        exit 1
      fi
      exec ${agent-vm}/bin/agent-vm "$@" run --tty zsh -l -c "opencode --auto"
    fi
    if [ "''${1:-}" = install ]; then
      echo "albert-code install is not needed here: agent-vm comes from Nix (home.nix)." >&2
      echo "Base VM: agent-vm setup   |   health: agent-vm doctor" >&2
      exit 1
    fi
    exec "$real" "$@"
  '';
in
{
  # Markdown preview for Dolphin (middle-click / right-click), own module.
  imports = [ ./md-preview.nix ];

  home.username = "jbouquillon";
  home.homeDirectory = "/home/jbouquillon";

  # Home Manager release this config was first written for. Do NOT bump it
  # when upgrading; it only controls defaults for backward compatibility.
  home.stateVersion = "26.05";

  # ---------------------------------------------------------------- packages
  # Search for packages: https://search.nixos.org/packages  (or `nix search nixpkgs foo`)
  home.packages = [
    unstable.claude-code # from nixpkgs-unstable: updates more often
    agent-vm             # from its own flake input (Lima built in: no `limactl` needed)
    albertCode           # wrapper, see the `let` block above

    # Handy command-line tools
    pkgs.ripgrep # rg: fast grep
    pkgs.fd      # fast find
    pkgs.jq      # JSON
    pkgs.htop
    pkgs.mdcat   # render Markdown in the terminal: `mdcat README.md`
    pkgs.scalingo # CLI for the Scalingo PaaS
    pkgs.gitleaks # detect secrets in git (pre-commit hook, see below)

    # Tools for editing Nix itself
    pkgs.nixd        # language server (VS Code: "Nix IDE" extension)
    pkgs.nixfmt      # formatter
    pkgs.nix-tree    # explore what is installed and why

    # YubiKey
    pkgs.yubikey-manager # `ykman info`, `ykman fido credentials list`
    pkgs.libfido2        # `fido2-token -L`: list connected FIDO keys
  ];

  # -------------------------------------------------------------------- zsh
  # Home Manager now owns ~/.zshrc and ~/.zshenv; edit here, not there.
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      save = 50000;
      ignoreSpace = true;    # a command starting with a space is not saved (use it for secrets)
      ignoreAllDups = true;  # keep only the latest copy of a repeated command
      expireDuplicatesFirst = true;
      ignorePatterns = [ "*API_KEY=*" "*TOKEN=*" "*sk-eyJ*" "*github_pat_*" ]; # never save secrets
    };
    shellAliases = {
      pbcopy = "xsel --clipboard --input";
      pbpaste = "xsel --clipboard --output";
      hms = "home-manager switch --flake ~/Documents/projets/dotfiles#jbouquillon";
      gs = "git status";
      gc = "git commit";
      gd = "git diff";
    };
    sessionVariables = {
      EDITOR = "vim";
      # albert-code writes its keys (ALBERT_API_KEY, GH_TOKEN...) to $ZSHENV.
      # ~/.zshenv is managed by Home Manager (read-only), so point it at the secrets file.
      ZSHENV = "${config.home.homeDirectory}/.config/secrets/env";
    };
    # Goes into ~/.zshenv: read by every zsh, including non-interactive `zsh -c`.
    envExtra = ''
      # Secrets live outside the Nix config (anything in /nix/store is world-readable).
      [ -r "$HOME/.config/secrets/env" ] && source "$HOME/.config/secrets/env"
    '';
  };

  # albert-code (and other local scripts) live in ~/.local/bin
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.starship.enable = true; # prompt (adds the `eval "$(starship init zsh)"` for you)

  # direnv: drop a `.envrc` containing `use flake` in a project and its dev
  # tools load automatically when you `cd` into it.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ------------------------------------------------------- git + YubiKey
  # Commits and tags are signed with an SSH key that lives on the YubiKey
  # (FIDO2 "sk" key): every commit asks you to touch the key.
  # ~/.ssh/id_ed25519_sk is only a handle; it is useless without the YubiKey.
  programs.git = {
    enable = true;
    signing = {
      format = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519_sk";
      signByDefault = true; # commits AND tags
    };
    settings = {
      user.name = "Julien Bouquillon";
      user.email = gitEmail;
      gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
      safe.bareRepository = "explicit";
      init.defaultBranch = "main";
      log.showSignature = false; # use `git log --show-signature` when you want to check
      alias.verify = "log --format='%G? %h %an %s' -10"; # G = good signature, N = none
      # Run the pre-commit hook below from every repo (core.hooksPath).
      core.hooksPath = "${config.home.homeDirectory}/.config/git/hooks";
    };
  };

  # Lets `git log --show-signature` verify your own commits.
  xdg.configFile."git/allowed_signers".text =
    ''${gitEmail} namespaces="git" ${signingPubKey}'';

  # Global pre-commit hook: refuse to stage a commit that contains secrets.
  # core.hooksPath above points every repo at this directory, so no `git init
  # --template` or per-repo setup is ever needed.
  home.file.".config/git/hooks/pre-commit" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      set -eu
      cd "$(git rev-parse --show-toplevel)"
      if command -v gitleaks >/dev/null 2>&1; then
        gitleaks protect --staged --verbose
      else
        echo "pre-commit: gitleaks not found in PATH — refusing to commit (run: hms)" >&2
        exit 1
      fi
    '';
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."github.com" = {
      # resident ("rk") FIDO key on the YubiKey, used to push/pull on GitHub
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519_sk_rk_github";
      IdentitiesOnly = "yes";
    };
  };

  # Lets Home Manager update itself and provides the `home-manager` command.
  programs.home-manager.enable = true;
}
