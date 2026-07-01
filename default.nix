/*
Bunkalunk package.

This derivation is a thin wrapper that facilitates using bunk and lunk as
callable tools from a project. It is impure, and not yet capable of spinning up
a clean, self-contained nix package. To use it, include it in your project, and
then prepare lunk by calling the script build-test-sysimage from the command
line, which will prepare the julia sysimage that the lunk wrapper links against.

*/

{ pkgs ? import <nixpkgs> {} }:

let
  project_root = builtins.toString ./.;
  runtimePythonPackages = ps: with ps; [ requests fitdecode h5py ];
  pythonEnv = pkgs.python3.withPackages runtimePythonPackages;

  bunk = pkgs.writeShellScriptBin "bunk" ''
    export PYTHONPATH=${project_root}/src/python:''${PYTHONPATH}
    exec ${pythonEnv}/bin/python -m bunkalunk.bunk "$@"
  '';

  lunk = pkgs.writeShellScriptBin "lunk" ''
    exec julia \
      --sysimage=${project_root}/src/julia/build/test_sysimage.so \
      --project=${project_root}/src/julia \
      ${project_root}/src/julia/src/cli.jl "$@"
  '';

  lunkJuliaTest = pkgs.writeShellScriptBin "julia-test" ''
    exec julia \
      --sysimage=${project_root}/src/julia/build/test_sysimage.so \
      --project=${project_root}/src/julia \
      "$@"
  '';

  lunkBuildTestSysimage = pkgs.writeShellScriptBin "build-test-sysimage" ''
    export PYTHONPATH=${project_root}/src/python:''${PYTHONPATH}
    mkdir -p ${project_root}/src/julia/build
    exec julia --project=${project_root}/src/julia/scripts \
      ${project_root}/src/julia/scripts/build_test_sysimage.jl \
      ${project_root}/src/julia/build/test_sysimage.so
  '';
in
{
  inherit runtimePythonPackages pythonEnv lunkJuliaTest lunkBuildTestSysimage;

  bunkAndLunk = pkgs.symlinkJoin {
    name = "bunkalunk-tools";
    paths = [ bunk lunk ];
  };
}
