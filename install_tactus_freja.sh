#!/usr/bin/env bash
# Install/repair a TACTUS Poetry environment on NSC Freja (AlmaLinux 9).
# Does not start ecFlow, submit Slurm jobs, change Git branches, or compile HARMONIE.
set -Eeuo pipefail

TACTUS_HOME="${TACTUS_HOME:-$HOME/repositories/tactus}"
TACTUS_REF="${TACTUS_REF:-v1.3.0}" # Used only for a NEW checkout
PY_MODULE="Python/3.10.4-bare-hpc1-gcc-2022a-eb"
GDAL_MODULE="GDAL/3.5.0-hpc1-gcc-2022a-eb"
ECFLOW_PREFIX="/software/sse2/freja_el9/manual/ecflow/5.12.4/hpc1-mamba-py3.10.4"
GDAL_SITE="/software/sse2/freja_el9/easybuild/pure/software/GDAL/3.5.0-foss-2022a/lib/python3.10/site-packages"
REPO_URL="https://github.com/ACCORD-NWP/tactus.git"

say() { printf '\n>>> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
trap 'echo "Installation stopped at line $LINENO (exit $?)." >&2' ERR

# Freja module command is a shell function: scripts may need to initialize Lmod.
if ! type module &>/dev/null; then
  for init in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /software/sse2/init/nsc_lmod_init.sh; do
    if [[ -f "$init" ]]; then source "$init"; break; fi
  done
fi
type module &>/dev/null || die "Lmod 'module' command is unavailable; log in with a Freja login shell."
module load "$PY_MODULE"
module load "$GDAL_MODULE"
[[ "$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" == "3.10" ]] || die "Python module did not provide Python 3.10."
[[ -d "$ECFLOW_PREFIX/lib/python3.10/site-packages/ecflow" ]] || die "ecFlow 5.12.4 Python 3.10 bindings missing: $ECFLOW_PREFIX"
[[ -d "$GDAL_SITE/osgeo" ]] || die "GDAL Python bindings missing: $GDAL_SITE"
[[ -x "$ECFLOW_PREFIX/bin/ecflow_client" ]] || die "ecflow_client missing from $ECFLOW_PREFIX/bin"

# Construct a reusable activation file; do not overwrite user-edited activation scripts.
ACTIVATE="$TACTUS_HOME/setup_tactus_freja.sh"
mkdir -p "$(dirname "$TACTUS_HOME")"
if [[ ! -d "$TACTUS_HOME/.git" ]]; then
  if [[ -e "$TACTUS_HOME" ]]; then die "Path exists but is not a Git checkout: $TACTUS_HOME"; fi
  say "Clone TACTUS $TACTUS_REF into $TACTUS_HOME"
  git clone --branch "$TACTUS_REF" "$REPO_URL" "$TACTUS_HOME"
else
  say "Using existing checkout; Git branch and modifications will be preserved"
fi
cd "$TACTUS_HOME"
if [[ -e "$ACTIVATE" ]]; then
  cp -p "$ACTIVATE" "${ACTIVATE}.backup.$(date +%Y%m%d_%H%M%S)"
fi
cat > "$ACTIVATE" <<'ACTIVATE_EOF'
#!/usr/bin/env bash
# Source with: source "$HOME/repositories/tactus/setup_tactus_freja.sh"
# Does not run model jobs and does not change Slurm allocations.
if ! type module &>/dev/null; then
  for init in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /software/sse2/init/nsc_lmod_init.sh; do
    if [[ -f "$init" ]]; then source "$init"; break; fi
  done
fi
type module &>/dev/null || { echo 'ERROR: Lmod not initialized' >&2; return 1 2>/dev/null || exit 1; }
module load Python/3.10.4-bare-hpc1-gcc-2022a-eb || return 1
module load GDAL/3.5.0-hpc1-gcc-2022a-eb || return 1
export TACTUS_HOME="${TACTUS_HOME:-$HOME/repositories/tactus}"
export ECFLOW_DIR="/software/sse2/freja_el9/manual/ecflow/5.12.4/hpc1-mamba-py3.10.4"
export ECFLOW_PYTHON310="$ECFLOW_DIR/lib/python3.10/site-packages"
export GDAL_PYTHON310="/software/sse2/freja_el9/easybuild/pure/software/GDAL/3.5.0-foss-2022a/lib/python3.10/site-packages"
# Avoid prepending duplicate paths when sourced repeatedly.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
case ":$PATH:" in *":$ECFLOW_DIR/bin:"*) ;; *) export PATH="$ECFLOW_DIR/bin:$PATH";; esac
case ":${PYTHONPATH:-}:" in *":$ECFLOW_PYTHON310:"*) ;; *) export PYTHONPATH="$ECFLOW_PYTHON310${PYTHONPATH:+:$PYTHONPATH}";; esac
case ":${PYTHONPATH:-}:" in *":$GDAL_PYTHON310:"*) ;; *) export PYTHONPATH="$GDAL_PYTHON310${PYTHONPATH:+:$PYTHONPATH}";; esac
# Do not set ECF_HOST/ECF_PORT: port and server must be assigned/verified separately.
ACTIVATE_EOF
chmod 755 "$ACTIVATE"
# An existing checkout's paths may be customized; explicitly override home to chosen checkout.
export TACTUS_HOME
# shellcheck disable=SC1090
source "$ACTIVATE"

if ! command -v poetry &>/dev/null; then
  say "Poetry missing; installing in user space using the official installer"
  command -v curl >/dev/null || die "curl not found"
  curl -fsSL https://install.python-poetry.org -o "${TMPDIR:-/tmp}/install-poetry-${USER}.py"
  python3 "${TMPDIR:-/tmp}/install-poetry-${USER}.py"
fi
command -v poetry >/dev/null || die "Poetry still not found after installation"
say "Poetry version: $(poetry --version)"

poetry config virtualenvs.in-project true --local
poetry env use "$(command -v python3)"
if [[ -f poetry.lock ]]; then
  if ! poetry check --lock >/dev/null 2>&1; then
    say "Lock file does not match pyproject.toml; regenerating lock (existing file backed up)"
    cp -p poetry.lock "poetry.lock.backup.$(date +%Y%m%d_%H%M%S)"
    poetry lock
  fi
else
  say "No lock file: creating poetry.lock"
  poetry lock
fi
say "Install dependencies and local TACTUS package"
poetry install --no-interaction

# Freja's host include in TACTUS v1.3.0 may be absent. Create ONLY that minimal file.
ARCHIVE_FILE="$TACTUS_HOME/tactus/data/config_files/include/archiving/freja.toml"
if [[ ! -f "$ARCHIVE_FILE" ]]; then
  printf '[archiving]\n' > "$ARCHIVE_FILE"
  say "Created minimal archiving include: $ARCHIVE_FILE (no production archiving configured)"
fi
# Do not change ecFlow port automatically: existing workflow ownership and server port must be verified.
SCHED="$TACTUS_HOME/tactus/data/config_files/include/scheduler/ecflow_freja.toml"
if [[ -f "$SCHED" ]] && grep -q '_set_port_from_user' "$SCHED"; then
  say "NOTICE: Scheduler ecf_port uses _set_port_from_user(...). If 'tactus show config' fails, set a valid INTEGER port reserved for your ecFlow server."
fi

say "Validate Python imports"
poetry run python - <<'PY'
import sys, importlib.metadata as metadata
import tactus, ecflow
from osgeo import gdal
print('Python:', sys.version.split()[0])
print('TACTUS:', metadata.version('tactus'), tactus.__file__)
print('ecFlow:', ecflow.__file__)
print('GDAL:', gdal.VersionInfo())
assert hasattr(ecflow, 'Client')
assert gdal.VersionInfo().startswith('305')
PY
poetry run tactus --version
say "Checking TACTUS configuration (log: $TACTUS_HOME/tactus_freja_config.log)"
if poetry run tactus show config > "$TACTUS_HOME/tactus_freja_config.log" 2>&1; then
  say "TACTUS configuration validated successfully"
else
  echo "WARNING: configuration needs adjustments; last 25 log lines:" >&2
  tail -25 "$TACTUS_HOME/tactus_freja_config.log" >&2
  echo "Python/Poetry installation passed; platform configuration requires attention." >&2
fi
say "FINISHED. For each login: cd '$TACTUS_HOME' && source '$ACTIVATE'"
