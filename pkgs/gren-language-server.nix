{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "gren-language-server-unofficial";
  version = "main-2024-01-16";

  src = fetchFromGitHub {
    owner = "lue-bird";
    repo = "gren-language-server-unofficial";
    rev = "06ba104";
    sha256 = "sha256-ouZyKcKa+Aa9X3Dmh1KgXL9E9FKZtGuAB6705/Y8GsI=";
  };

  #cargoHash = lib.fakeHash;
  cargoHash = "sha256-ZxLAVV8UYkHDtC4wEjCXKGTlOFrLoy5t0eesZkXn6ug=";

  meta = with lib; {
    description = "Unofficial LSP implementation for Gren";
    homepage = "https://github.com/lue-bird/gren-language-server-unofficial";
    maintainers = [ ];
  };
}
