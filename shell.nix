# Minimal empty shell.nix for this project
let
  pkgs = import <nixpkgs> {};
  bunkalunk = import ./default.nix { inherit pkgs; };
  # Install opencode outside of nix so it can autoupdate, but project-level
  # config can live here
  opencodeConfig = builtins.toJSON {
    instructions = [ "docs/spec.md" ];
  };

  lunkJuliaDev = pkgs.writeShellScriptBin "julia-dev" ''
    export JULIA_PROJECT="$PWD/src/julia"
    export BUNK_DEV_SYSIMAGE="$PWD/src/julia/build/dev_sysimage.so"
    exec julia --sysimage="$BUNK_DEV_SYSIMAGE" --project="$JULIA_PROJECT" "$@"
  '';

  lunkJuliaCtags = pkgs.writeShellScriptBin "julia-ctags" ''
    exec ctags -R \
      --languages=Julia \
      --output-format=etags \
      -f "$PWD/src/julia/TAGS" \
      "$PWD/src/julia/src" \
      "$PWD/src/julia/test" \
      "$PWD/src/julia/scripts"
  '';
in
pkgs.mkShell {
  buildInputs = [
    bunkalunk.pythonDevEnv
    lunkJuliaDev
    lunkJuliaCtags
    bunkalunk.lunkJuliaTest
    bunkalunk.lunkBuildTestSysimage
    bunkalunk.bunkAndLunk
  ]
  ++ (with pkgs;
    [
      universal-ctags
      ruff
      sqlite
    ]);

  TMPDIR = "/tmp";  # Julia tries (and fails) to write tmpdata to nix-store without this

  # Setup pythonpath and db root in a shell hook
  shellHook = ''
    export PYTHON=${bunkalunk.pythonEnv}/bin/python  # Allows Julia to see shell's python
    export PYTHONPATH=''${PYTHONPATH}:''${PWD}/src/python
    export MYPYPATH=''${PYTHONPATH}/typings
    export JULIA_PROJECT=''${PWD}/src/julia
    export PYTEST_DIR=''${PWD}/src/python/tests
    export PATH=/home/taylor/.julia/bin:''${PATH}
    export OPENCODE_CONFIG_CONTENT='${opencodeConfig}'

    export BUNK_DEV_SYSIMAGE=''${PWD}/src/julia/build/dev_sysimage.so
    export BUNK_TEST_SYSIMAGE=''${PWD}/src/julia/build/test_sysimage.so
  '';
}
