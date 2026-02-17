{
  description = "Blaix Flakes";

  inputs = {
    # unstable
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    home-manager.url = "github:nix-community/home-manager/master";

    # versioned
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    #nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    #home-manager.url = "github:nix-community/home-manager/release-25.05";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # doitanyway web application
    doitanyway.url = "git+ssh://git@github.com/blaix/doitanyway.new.git";
    doitanyway.inputs.nixpkgs.follows = "nixpkgs";

    # growth web application
    growth.url = "github:blaix/growth";
    growth.inputs.nixpkgs.follows = "nixpkgs";

    # mycomics web application
    mycomics.url = "github:blaix/mycomics";
    mycomics.inputs.nixpkgs.follows = "nixpkgs";

    # myrecords web application
    myrecords.url = "github:blaix/myrecords";
    myrecords.inputs.nixpkgs.follows = "nixpkgs";

    # disko for declarative disk management
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # lix is failing to build
    #lix-module = {
    #  url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};
  };

  #outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, lix-module, ... }: {
  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, disko, ... }:
    let
      homeManagerConfig = {
        home-manager.users.justin = import ./home.nix;
      };

      mkDarwinSystem = hostname: nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          #lix-module.nixosModules.default
          ./hosts/mac/${hostname}.nix
          home-manager.darwinModules.home-manager homeManagerConfig
        ];
      };

      mkNixosSystem = { hostname, system ? "aarch64-linux" }: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          #lix-module.nixosModules.default
          ./hosts/nixos/${hostname}.nix
          home-manager.nixosModules.home-manager homeManagerConfig
        ];
      };
    in {
      # macs
      darwinConfigurations = {
        arwen = mkDarwinSystem "arwen";
        bilbo = mkDarwinSystem "bilbo";
      };

      # nixos
      nixosConfigurations = {
        orb = mkNixosSystem { hostname = "orb"; }; # my orbstack vm
        blaixapps = mkNixosSystem { hostname = "blaixapps"; system = "x86_64-linux"; }; # multi-app server
        blaixapps-base = mkNixosSystem { hostname = "blaixapps-base"; system = "x86_64-linux"; }; # base-level nixos server install
      };
    };
}
