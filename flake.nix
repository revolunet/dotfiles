{
  # A flake is a folder with a flake.nix: "inputs" (pinned dependencies,
  # locked by version in flake.lock) and "outputs" (what this flake produces).
  description = "My user environment (Home Manager) on Sécurix/NixOS";

  inputs = {
    # Stable package set, same release as the system (26.05).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Rolling package set, only for things that move fast (e.g. claude-code).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # Reuse our nixpkgs instead of downloading a second copy.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Any flake on GitHub can be an input.
    agent-vm.url = "github:sylvinus/agent-vm";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, agent-vm, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # replaces NIXPKGS_ALLOW_UNFREE=1 --impure
      };
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      # Apply with: home-manager switch --flake .#jbouquillon
      homeConfigurations.jbouquillon = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        # Extra values passed to home.nix as function arguments.
        extraSpecialArgs = {
          inherit unstable;
          agent-vm = agent-vm.packages.${system}.default;
        };
        modules = [ ./home.nix ];
      };
    };
}
