# Minimal empty shell.nix for this project
let
  pkgs = import <nixpkgs> {};

  myPython = pkgs.python3.override {
    packageOverrides = self: super: {
      # Provide ua-generator in the package set via an override.
      ua_generator = super.buildPythonPackage rec {
        pname = "ua-generator";
        version = "2.0.24";
        src = pkgs.fetchFromGitHub {
          owner = "iamdual";
          repo = "ua-generator";
          rev = "2.0.24";
          sha256 = "sha256-eqrstqwbXw3KVaTmBCXAwDQ++IC4pSVqye3tmmnIKe0=";
        };
        # Use legacy setuptools build via pyproject
        pyproject = true;
        nativeBuildInputs = with pkgs.python3Packages; [ setuptools ];
        propagatedBuildInputs = with pkgs.python3Packages; [];
        pythonImportsCheck = [ "ua_generator" ];
      };

      garminconnect = super.garminconnect.overridePythonAttrs (old: {
        src = pkgs.fetchFromGitHub {
          owner = "cyberjunky";
          repo = "python-garminconnect";
          rev = "0.3.1";
          sha256 = "sha256-31zCAJAr3f1nevd61a3dCEZ6vjPhW0uLHhnnAUG03Yc=";
        };

        dependencies = (with pkgs.python3Packages; [
          curl-cffi
          requests
          self.ua_generator
        ]);
      });

    };
  };
  
  pythonEnv = myPython.withPackages (ps: with ps; [
    requests
    fitdecode
    h5py
    # garminconnect

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


in
pkgs.mkShell {
  buildInputs = [ pythonEnv ] ++ (with pkgs; [ ruff ]);

  # Setup pythonpath and db root in a shell hook
  shellHook = ''
    export PYTHONPATH=''${PYTHONPATH}:''${PWD}/src/python
    export BUNKALUNK_DB_ROOT=''${PWD}/source_archive
  '';
}
