# Minimal empty shell.nix for this project
let
  pkgs = import <nixpkgs> {};

  myPython = pkgs.python3;
  pythonEnv = myPython.withPackages (ps: with ps; [
    requests
    fitdecode
    h5py

    ipython
    pytest
    
    python-lsp-server
    python-lsp-ruff   # linting + formatting (replaces pycodestyle, pyflakes, autopep8)
    pylsp-rope        # rope provider for pylsp
    pylsp-mypy        # type checking

    # Plugin dependencies (explicit so nix-shell always has them on PATH)
    rope
    mypy
  ]);
  # Install opencode outside of nix so it can autoupdate, but project-level
  # config can live here
  opencodeConfig = builtins.toJSON {
    instructions = [ "docs/spec.md" ];
  };

  lunkJuliaDev = pkgs.writeShellScriptBin "julia-dev" ''
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
    export JULIA_PROJECT="$PROJECT_ROOT/src/julia"
    export BUNK_DEV_SYSIMAGE="$PROJECT_ROOT/src/julia/dev_sysimage.so"
    exec julia --sysimage="$BUNK_DEV_SYSIMAGE" --project="$JULIA_PROJECT" "$@"
  '';

  lunkBuildSysimage = pkgs.writeShellScriptBin "build-sysimage" ''
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
    unset JULIA_PROJECT JULIA_LOAD_PATH
    exec julia --project="$PROJECT_ROOT/src/julia/scripts" \
      "$PROJECT_ROOT/src/julia/scripts/build_sysimage.jl"
  '';
in
pkgs.mkShell {
  buildInputs = [ pythonEnv lunkJuliaDev lunkBuildSysimage ]
                ++ (with pkgs;
                  [
                    ruff
                    sqlite
                  ]);

  TMPDIR = "/tmp";  # Julia tries (and fails) to write tmpdata to nix-store without this

  # Setup pythonpath and db root in a shell hook
  shellHook = ''
    export PYTHON=${pythonEnv}/bin/python  # Allows Julia to see shell's python
    export PYTHONPATH=''${PYTHONPATH}:''${PWD}/src/python
    export MYPYPATH=''${PYTHONPATH}/typings
    export JULIA_PROJECT=''${PWD}/src/julia
    export PYTEST_DIR=''${PWD}/src/python/tests
    export PATH=/home/taylor/.julia/bin:''${PATH}
    export OPENCODE_CONFIG_CONTENT='${opencodeConfig}'

    export BUNK_DEV_SYSIMAGE=''${PWD}/src/julia/dev_sysimage.so
  '';
}
