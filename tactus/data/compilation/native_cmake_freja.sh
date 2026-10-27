#!/usr/bin/env bash
set -euo pipefail
# This runs inside a Slurm allocation launched by the TACTUS ecFlow task.
: "${IAL_DIR:?TACTUS must set IAL_DIR}"
: "${NATIVE_CASE_DIR:?TACTUS must set NATIVE_CASE_DIR}"
[[ -f "$IAL_DIR/src/CMakeLists.txt" || -f "$IAL_DIR/.gitmodules" ]] || { echo "Missing HarmonieCSC source: $IAL_DIR" >&2; exit 1; }
WORK="$NATIVE_CASE_DIR/native-cmake"
PREBUILD="$WORK/build-prerequisites"
BUILD="$WORK/build"
INSTALL="$WORK/install"
BINDIR="$INSTALL/bin"
CONFIG="$IAL_DIR/util/cmake/config/config.freja.Intel.json"
NPROC="${SLURM_CPUS_PER_TASK:-1}"
[[ -n "${SLURM_JOB_ID:-}" ]] || { echo 'ERROR: Slurm allocation missing. Do not compile on login node.' >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "Missing config: $CONFIG" >&2; exit 1; }
source /software/sse2/init/nsc_lmod_init.sh
module -q purge
module load buildenv-intel/2023a-eb
module load FFTW/3.3.10-hpc1
module load ecbuild/3.9.1-hpc1-bdist
module load eccodes/2.32.0-ENABLE-AEC-hpc1
module load netCDF-HDF5/4.9.2-1.12.2-hpc1
module load CMake/3.27.9
module load smhi-el9-modules
module load fypp
module load Python/3.10.4-bare-hpc1-gcc-2022a-eb
export CC=mpiicc CXX=mpiicpc FC=mpiifort F77=mpiifort F90=mpiifort
export HM_DATA="$WORK" HM_LIB="$IAL_DIR" CMAKE_CONFIG=config.freja.Intel.json
export CMAKE_BUILD_TYPE=Release FP_PRECISION=double FP_SUFFIX="" INSTALL_DIR="$INSTALL" BINDIR
export CMAKE_PREFIX_PATH="$INSTALL${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PATH="$HOME/.local/bin:$INSTALL/bin:$PATH"
unset PYTHONHOME VIRTUAL_ENV PYTHONNOUSERSITE
export PYTHONPATH="$HOME/.local/lib/python3.10/site-packages"
FYPP="$HOME/.local/bin/fypp"
[[ -x "$FYPP" ]] || { echo "Missing Fypp: $FYPP" >&2; exit 1; }
python3 -c 'import yaml,fypp; print("PyYAML",yaml.__version__,"Fypp",fypp.__file__)'
"$FYPP" --version
mkdir -p "$WORK" "$PREBUILD" "$BUILD" "$INSTALL"
echo "==== Git and submodules ===="
git -C "$IAL_DIR" submodule update --init --recursive
test -f "$IAL_DIR/src/CMakeLists.txt"
echo "==== Prerequisites ===="
for project in bufr_405 gribex_370 rgb_001 dummies_006/mpidummy; do
    d="$PREBUILD/${project//\//-}"
    cmake -S "$IAL_DIR/util/auxlibs/$project" -B "$d" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL" -DCONFIG_FILE="$CONFIG"
    cmake --build "$d" --parallel "$NPROC"
    cmake --install "$d"
done
cmake -S "$IAL_DIR/util/external" -B "$PREBUILD/external" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL" -DCONFIG_FILE="$CONFIG"
cmake --build "$PREBUILD/external" --parallel "$NPROC"
echo "==== Main IAL configuration ===="
cmake -S "$IAL_DIR/src" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALL" -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=YES -DCONFIG_FILE="$CONFIG" -DFYPP_EXECUTABLE="$FYPP"
echo "==== Main IAL build ===="
cmake --build "$BUILD" --parallel "$NPROC"
echo "==== Install ===="
cmake --build "$BUILD" --target install --parallel "$NPROC"
for pair in ioassign:IOASSIGN ODBTOOLS:shuffle dcagen:dcagen.x OFFLINE:SURFEX FODBSQL:odbsql.x; do
    src="${pair%%:*}"; dst="${pair##*:}"
    [[ ! -f "$BINDIR/$src" ]] || cp -p "$BINDIR/$src" "$BINDIR/$dst"
done
for exe in MASTERODB FESTAT BLEND BLEND3 ADDPERT PERTSURF OFFLINE PGD PREP; do
    [[ -x "$BINDIR/$exe" ]] || { echo "ERROR: missing executable $exe" >&2; exit 1; }
    echo "PASS: $exe"
done
echo "NATIVE CMAKE R64 BUILD SUCCESSFUL: $BINDIR"
