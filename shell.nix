# Minimal empty shell.nix for this project
let
  pkgs = import <nixpkgs> {};
  bunkalunk = import ./default.nix { inherit pkgs; };

  pythonDevEnv = pkgs.python3.withPackages (ps: with ps;
    bunkalunk.runtimePythonPackages ps ++ [
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

  lunkJuliaCtags = pkgs.writeShellScriptBin "julia-ctags" ''
    exec ctags -R \
      --languages=Julia \
      --output-format=etags \
      -f "${project_root}/src/julia/TAGS" \
      "${project_root}/src/julia/src" \
      "${project_root}/src/julia/test" \
      "${project_root}/src/julia/scripts"
  '';

  project_root = builtins.toString ./.;
  lunkJuliaDev = pkgs.writeShellScriptBin "julia-dev" ''
    exec julia \
      --sysimage=${project_root}/src/julia/build/dev_sysimage.so \
      --project=${project_root}/src/julia \
      "$@"
  '';

  lunkBuildDevSysimage = pkgs.writeShellScriptBin "build-dev-sysimage" ''
    unset JULIA_PROJECT
    mkdir -p ${project_root}/src/julia/build
    exec julia --project=${project_root}/src/julia/scripts/dev_sysimage \
      ${project_root}/src/julia/scripts/dev_sysimage/build.jl \
      ${project_root}/src/julia/build/dev_sysimage.so
  '';

in
pkgs.mkShell {
  buildInputs = [
    pythonDevEnv
    lunkJuliaDev
    lunkBuildDevSysimage
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
      sqlfluff
    ]);

  TMPDIR = "/tmp";  # Julia tries (and fails) to write tmpdata to nix-store without this

  # Setup pythonpath and db root in a shell hook
  shellHook = ''
    export PYTHON=${bunkalunk.pythonEnv}/bin/python  # Allows Julia to see shell's python
    export PYTHONPATH=''${PYTHONPATH}:''${PWD}/src/python
    export MYPY_BACKGROUND_COMMAND="mypy --python-executable=''${PYTHON}"
    export JULIA_PROJECT=''${PWD}/src/julia
    export PYTEST_DIR=''${PWD}/src/python/tests
    export PATH=/home/taylor/.julia/bin:''${PATH}
    export OPENCODE_CONFIG_CONTENT='${opencodeConfig}'

    export BUNK_DEV_SYSIMAGE=''${PWD}/src/julia/build/dev_sysimage.so
    export BUNK_TEST_SYSIMAGE=''${PWD}/src/julia/build/test_sysimage.so
  '';
}
