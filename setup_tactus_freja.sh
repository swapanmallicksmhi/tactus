
#!/usr/bin/env bash
# ============================================================
# TACTUS v1.4.0 - NSC Freja environment setup
# Python 3.10.4 / GDAL 3.5.0 / ecFlow 5.12.4
# Native CMake compilation / Intel 2023a
#
# Source with:
# source "$HOME/repositories/tactus/setup_tactus_freja.sh"
#
# ============================================================

# Initialize Lmod if necessary
if ! type module &>/dev/null; then
  for init in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /software/sse2/init/nsc_lmod_init.sh; do
    if [[ -f "$init" ]]; then source "$init"; break; fi
  done
fi

type module &>/dev/null || { echo "ERROR: Lmod not initialized" >&2; return 1 2>/dev/null || exit 1; }

# ============================================================
# Load Freja Python and GDAL modules
# ============================================================
module load Python/3.10.4-bare-hpc1-gcc-2022a-eb || { return 1 2>/dev/null || exit 1; }
module load GDAL/3.5.0-hpc1-gcc-2022a-eb || { return 1 2>/dev/null || exit 1; }

# ============================================================
# TACTUS and ecFlow paths
# ============================================================
export TACTUS_HOME="${TACTUS_HOME:-$HOME/repositories/tactus}"
export ECFLOW_DIR="/software/sse2/freja_el9/manual/ecflow/5.12.4/hpc1-mamba-py3.10.4"
export ECFLOW_PYTHON310="$ECFLOW_DIR/lib/python3.10/site-packages"
export GDAL_PYTHON310="/software/sse2/freja_el9/easybuild/pure/software/GDAL/3.5.0-foss-2022a/lib/python3.10/site-packages"
export TACTUS_GDAL_FIRST="$TACTUS_HOME/diagnostics/gdal_first"

# ============================================================
# Add executable paths without duplicates
# ============================================================
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$ECFLOW_DIR/bin:"*) ;;
  *) export PATH="$ECFLOW_DIR/bin:$PATH" ;;
esac

# ============================================================
# Python import paths
#
# IMPORTANT:
# The GDAL-first directory must always be first.
# Python sitecustomize.py imports GDAL before ecCodes.
#
# This avoids the previously reproduced LDAP cleanup crash
# caused by the ecCodes -> GDAL import order.
# ============================================================

# Remove previously inserted copies of managed paths
_TACTUS_PYTHONPATH=""
_OLD_PYTHONPATH="${PYTHONPATH:-}"

if [[ -n "$_OLD_PYTHONPATH" ]]; then
  IFS=':' read -r -a _TACTUS_PATHS <<< "$_OLD_PYTHONPATH"
  for _TACTUS_PATH in "${_TACTUS_PATHS[@]}"; do
    [[ -z "$_TACTUS_PATH" ]] && continue
    case "$_TACTUS_PATH" in
      "$TACTUS_GDAL_FIRST"|"$GDAL_PYTHON310"|"$ECFLOW_PYTHON310") continue ;;
    esac
    case ":$_TACTUS_PYTHONPATH:" in
      *":$_TACTUS_PATH:"*) ;;
      *) _TACTUS_PYTHONPATH="${_TACTUS_PYTHONPATH:+$_TACTUS_PYTHONPATH:}$_TACTUS_PATH" ;;
    esac
  done
fi

export PYTHONPATH="$TACTUS_GDAL_FIRST:$GDAL_PYTHON310:$ECFLOW_PYTHON310${_TACTUS_PYTHONPATH:+:$_TACTUS_PYTHONPATH}"

unset _TACTUS_PYTHONPATH _OLD_PYTHONPATH _TACTUS_PATHS _TACTUS_PATH

# ============================================================
# Create and verify GDAL-first startup module
# ============================================================
if [[ ! -f "$TACTUS_GDAL_FIRST/sitecustomize.py" ]]; then
  echo "ERROR: Missing GDAL-first startup module:" >&2
  echo "$TACTUS_GDAL_FIRST/sitecustomize.py" >&2
  return 1 2>/dev/null || exit 1
fi
