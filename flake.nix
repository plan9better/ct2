{
  description = "A Nix flake for building CTranslate2 with optional dependencies (CUDA, MKL, etc.)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgsPybind11.url = "github:NixOS/nixpkgs/080a4a27f206d07724b88da096e27ef63401a504";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgsPybind11,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        pkgsPb11 = import nixpkgsPybind11 {inherit system;};
        inherit (pkgsPb11.python312Packages) pybind11;
        inherit
          (pkgs.python3Packages)
          buildPythonPackage
          numpy
          pyyaml
          setuptools
          pytestCheckHook
          torch
          transformers
          wurlitzer
          ;

        inherit
          (pkgs)
          lib
          ;

        cmakeBool = b:
          if b
          then "ON"
          else "OFF";

        buildCTranslate2 = {
          withMkl ? false,
          mkl,
          withCUDA ? false,
          withCuDNN ? false,
          cudaPackages,
          withOneDNN ? false,
          oneDNN,
          withOpenblas ? true,
          openblas,
          withRuy ? true,
          ...
        }:
          pkgs.stdenv.mkDerivation {
            pname = "ctranslate2";
            version = "dev";
            src = ./ctranslate2;

            nativeBuildInputs =
              [pkgs.cmake]
              ++ lib.optionals withCUDA [
                cudaPackages.cuda_nvcc
              ];

            cmakeFlags =
              [
                "-DOPENMP_RUNTIME=COMP"
                "-DWITH_CUDA=${cmakeBool withCUDA}"
                "-DWITH_CUDNN=${cmakeBool withCuDNN}"
                "-DWITH_DNNL=${cmakeBool withOneDNN}"
                "-DWITH_OPENBLAS=${cmakeBool withOpenblas}"
                "-DWITH_RUY=${cmakeBool withRuy}"
                "-DWITH_MKL=${cmakeBool withMkl}"
              ]
              ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin "-DWITH_ACCELERATE=ON";

            buildInputs =
              lib.optionals withMkl [mkl]
              ++ lib.optionals withCUDA [
                cudaPackages.cuda_cccl
                cudaPackages.cuda_cudart
                cudaPackages.libcublas
                cudaPackages.libcurand
              ]
              ++ lib.optionals (withCUDA && withCuDNN) [
                cudaPackages.cudnn
              ]
              ++ lib.optionals withOneDNN [oneDNN]
              ++ lib.optionals withOpenblas [openblas]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                pkgs.llvmPackages.openmp
              ];
          };

        ctranslate2-cpp = buildCTranslate2 {
          inherit (pkgs) openblas;
          withOpenblas = true;
          withMkl = false;
          withCUDA = false;
          mkl = null;
          cudaPackages = null;
          oneDNN = null;
        };

        # 2. Python Bindings Build (uses the C++ library output)
        ctranslate2-python = buildPythonPackage {
          # inherit (ctranslate2-cpp) pname version src;

          # The CTranslate2 Python bindings are in a subdirectory
          # sourceRoot = ./ctranslate2/python;
          pname = "ctranslate2";
          version = "dev";
          src = ./ctranslate2/python;
          pyproject = true;

          build-system = [
            pybind11
            setuptools
          ];

          # This is the crucial link: The Python bindings must link against the C++ libraries
          buildInputs = [ctranslate2-cpp];

          dependencies = [
            numpy
            pyyaml
          ];

          # pythonImportsCheck = [
          #   "ctranslate2"
          #   "ctranslate2.converters"
          #   "ctranslate2.models"
          #   "ctranslate2.specs"
          # ];

          # nativeCheckInputs = [
          #   pytestCheckHook
          #   torch
          #   transformers
          #   wurlitzer
          # ];

          # preCheck = ''
          #   # run tests against build result, not sources
          #   rm -rf ctranslate2
          #   export HOME=$TMPDIR
          # '';

          # disabledTestPaths = [
          #   # TODO: ModuleNotFoundError: No module named 'opennmt'
          #   "tests/test_opennmt_tf.py"
          #   # OSError: We couldn't connect to 'https://huggingface.co' to load this file
          #   "tests/test_transformers.py"
          # ];
        };
      in {
        packages = {
          # C++ library
          "ctranslate2-openblas" = ctranslate2-cpp;

          # Python package
          "ctranslate2-python" = ctranslate2-python;

          ctranslate2-cuda = lib.optional pkgs.stdenv.hostPlatform.isLinux (
            let
              cudaPkgs = pkgs.makeCudaPackages {};
            in
              buildCTranslate2 {
                inherit (pkgs) openblas;
                withOpenblas = false;
                withCUDA = true;
                withCuDNN = true;
                cudaPackages = cudaPkgs;
                mkl = null;
                oneDNN = null;
              }
          );

          default = self.packages.${system}.ctranslate2-python;
        };

        devShells.ctranslate2 = pkgs.mkShell {
          name = "ctranslate2-dev";
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.gcc
            pkgs.git
          ];
          buildInputs = [
            pkgs.openblas
            pkgs.llvmPackages.openmp
          ];
        };

        devShells.default = pkgs.mkShell {
          name = "python-ct2";

          buildInputs = [
            self.packages.${system}.ctranslate2-python
            pkgs.uv
          ];

          shellHook = ''
            echo "Nix-built CTranslate2 Python package is available in the shell."
            echo "You can import 'ctranslate2' directly in Python."
            echo "Use 'uv' to manage other project-specific dependencies."
          '';
        };
      }
    );
}
