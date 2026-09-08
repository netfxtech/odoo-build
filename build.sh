#!/usr/bin/env bash
#
# Build the Odoo image, pulling the GitLab credential from Bitwarden Secrets
# Manager instead of keeping a .netrc on disk.
#
# The Dockerfile clones git.netfxtech.cloud/odoo/enterprise.git behind a
# required BuildKit secret (`--mount=type=secret,id=gitlab_netrc,target=/root/.netrc`).
# This script fetches the read-only GitLab PAT from BWS, renders it as netrc
# content, and hands it to buildx through an environment variable — the
# credential never touches the filesystem and never enters the build context.
#
# If $HOME/.config/bws/gitlab.netrc exists (export GITLAB_NETRC=<pat>), it is
# used instead and Bitwarden is skipped entirely. Override the path with
# GITLAB_NETRC_FILE.
#
#   ./build.sh                       # build :production with defaults
#   ./build.sh --target builder      # stop at the builder stage
#   ./build.sh --tag odoo:test       # custom tag
#   ./build.sh --emit-netrc ./nrc    # write the netrc out instead of building
#   ./build.sh -- --no-cache         # pass extra flags through to buildx
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- tunables (all env-overridable) -----------------------------------------
BWS_SECRET_KEY="${BWS_SECRET_KEY:-GITLAB_NETRC}"   # read-only repo scope
BWS_SECRET_ID="${BWS_SECRET_ID:-}"                 # set to skip the key lookup
TOKEN_ENV_FILE="${TOKEN_ENV_FILE:-$HOME/.config/bws/token.env}"
GITLAB_NETRC_FILE="${GITLAB_NETRC_FILE:-$HOME/.config/bws/gitlab.netrc}"  # local override, skips Bitwarden entirely
GIT_HOST="${GIT_HOST:-git.netfxtech.cloud}"
GIT_LOGIN="${GIT_LOGIN:-oauth2}"
IMAGE_TAG="${IMAGE_TAG:-odoo-build:19.0}"
ODOO_VERSION="${ODOO_VERSION:-19.0}"
ENTERPRISE_REF="${ENTERPRISE_REF:-19.0}"
BUILD_TARGET="${BUILD_TARGET:-production}"

emit_netrc=""
declare -a extra_args=()

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }

usage() { sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)      BUILD_TARGET="${2:?--target needs a value}"; shift 2 ;;
    --tag|-t)      IMAGE_TAG="${2:?--tag needs a value}"; shift 2 ;;
    --ref)         ENTERPRISE_REF="${2:?--ref needs a value}"; shift 2 ;;
    --secret-key)  BWS_SECRET_KEY="${2:?--secret-key needs a value}"; BWS_SECRET_ID=""; shift 2 ;;
    --emit-netrc)  emit_netrc="${2:?--emit-netrc needs a path}"; shift 2 ;;
    -h|--help)     usage ;;
    --)            shift; extra_args=("$@"); break ;;
    *)             die "unknown argument: $1 (use -- to pass flags to buildx)" ;;
  esac
done

# --- preflight ---------------------------------------------------------------
[ -f "$SCRIPT_DIR/Dockerfile" ] || die "no Dockerfile in $SCRIPT_DIR"

# --- resolve the secret ------------------------------------------------------
if [ -r "$GITLAB_NETRC_FILE" ]; then
  # Local override — skips Bitwarden entirely. Expects the file to export
  # GITLAB_NETRC with the raw GitLab PAT.
  info "using local override at $GITLAB_NETRC_FILE (skipping Bitwarden)"
  # shellcheck disable=SC1090
  . "$GITLAB_NETRC_FILE"
  GITLAB_PAT="${GITLAB_NETRC:-}"
  [ -n "$GITLAB_PAT" ] || die "$GITLAB_NETRC_FILE did not set GITLAB_NETRC"
else
  command -v bws >/dev/null || die "bws not found on PATH"
  command -v jq  >/dev/null || die "jq not found on PATH"

  # Load the BWS access token if it isn't already exported (e.g. non-interactive
  # shells and CI, which never source ~/.bashrc).
  if [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -r "$TOKEN_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$TOKEN_ENV_FILE"
  fi
  [ -n "${BWS_ACCESS_TOKEN:-}" ] || die "BWS_ACCESS_TOKEN not set and $TOKEN_ENV_FILE unreadable"
  export BWS_ACCESS_TOKEN

  if [ -z "$BWS_SECRET_ID" ]; then
    info "resolving secret '$BWS_SECRET_KEY' in Bitwarden"
    BWS_SECRET_ID="$(
      bws secret list -o json \
        | jq -r --arg k "$BWS_SECRET_KEY" '[.[] | select(.key == $k)] | .[0].id // empty'
    )" || die "bws secret list failed (bad token, or vault unreachable?)"
    [ -n "$BWS_SECRET_ID" ] || die "no secret named '$BWS_SECRET_KEY' visible to this machine account"
  fi

  GITLAB_PAT="$(bws secret get "$BWS_SECRET_ID" -o json | jq -r '.value // empty')" \
    || die "failed to read secret $BWS_SECRET_ID"
  [ -n "$GITLAB_PAT" ] || die "secret '$BWS_SECRET_KEY' is empty"
fi

case "$GITLAB_PAT" in
  glpat-*) ;;
  *) info "warning: secret does not start with 'glpat-'; continuing anyway" ;;
esac

# Assembled without $(...) on purpose: command substitution strips trailing
# newlines, and the netrc must end with one so the final line isn't truncated.
GITLAB_NETRC_CONTENT="machine ${GIT_HOST}"$'\n'"login ${GIT_LOGIN}"$'\n'"password ${GITLAB_PAT}"$'\n'
export GITLAB_NETRC_CONTENT
unset GITLAB_PAT

# Scrub the credential from the environment on any exit path.
cleanup() { unset GITLAB_NETRC_CONTENT; }
trap cleanup EXIT INT TERM

# --- emit-only mode ----------------------------------------------------------
if [ -n "$emit_netrc" ]; then
  ( umask 077; printf '%s' "$GITLAB_NETRC_CONTENT" > "$emit_netrc" )
  info "wrote netrc to $emit_netrc (mode 600) — delete it when you are done"
  exit 0
fi

# --- build -------------------------------------------------------------------
info "building $IMAGE_TAG (target=$BUILD_TARGET, enterprise ref=$ENTERPRISE_REF)"

exec docker buildx build \
  --file "$SCRIPT_DIR/Dockerfile" \
  --target "$BUILD_TARGET" \
  --tag "$IMAGE_TAG" \
  --build-arg "ODOO_VERSION=$ODOO_VERSION" \
  --build-arg "ENTERPRISE_REF=$ENTERPRISE_REF" \
  --secret "id=gitlab_netrc,env=GITLAB_NETRC_CONTENT" \
  --load \
  "${extra_args[@]}" \
  "$SCRIPT_DIR"
