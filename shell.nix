# Minimal empty shell.nix for this project
let
  pkgs = import <nixpkgs> {};

  runtimePythonPackages = ps: with ps; [ requests fitdecode h5py ];

  pythonDevEnv = pkgs.python3.withPackages (ps: with ps;
    runtimePythonPackages ps ++ [
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

  project_root = builtins.toString ./.;
  build_root = builtins.toString ./build;

  lunkJuliaCtags = pkgs.writeShellScriptBin "julia-ctags" ''
    exec ctags -R \
      --languages=Julia --output-format=etags \
      -f "${build_root}/julia/TAGS" \
      "${project_root}/src/julia/src" \
      "${project_root}/src/julia/test" \
      "${project_root}/src/julia/scripts"
  '';

  lunkJuliaDev = pkgs.writeShellScriptBin "julia-dev" ''
    exec julia \
      --sysimage=${build_root}/julia/sysimages/dev_sysimage.so \
      --project=${project_root}/src/julia \
      "$@"
  '';

in
pkgs.mkShell {
  buildInputs = [
    pythonDevEnv
    lunkJuliaDev
    lunkJuliaCtags
  ]
  ++ (with pkgs;
    [
      universal-ctags
      ruff
      sqlite
      sqlfluff
    ]);

  TMPDIR = "/tmp";  # Julia tries (and fails) to write tmpdata to nix-store without this

  # Setup pythonpath and db root in a shell hook
  shellHook = ''
    export PYTHON=${pythonDevEnv}/bin/python  # Allows Julia to see shell's python
    export PYTHONPATH=''${PYTHONPATH}:''${PWD}/src/python
    export MYPY_BACKGROUND_COMMAND="mypy --python-executable=''${PYTHON}"
    export JULIA_PROJECT=''${PWD}/src/julia
    export PYTEST_DIR=''${PWD}/src/python/tests
    export PATH=/home/taylor/.julia/bin:''${PATH}
    export OPENCODE_CONFIG_CONTENT='${opencodeConfig}'
  '';
}
