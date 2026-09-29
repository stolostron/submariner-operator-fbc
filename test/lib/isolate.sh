#!/bin/bash
# Re-execute the candidate (including uncommitted files) in a disposable repo.
# Source this before any test can mutate its checkout. Nested tests reuse it.
isolate_test() {
  local root script fixture status=0
  script=$(realpath "$1")
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  if [ "${FBC_TEST_SANDBOX:-}" = "$root" ] && [ -f "$root/.fbc-test-sandbox" ]; then
    cd "$root" || return 1
    return
  fi
  fixture=$(mktemp -d)
  # Quote the path into the trap: local variables can leave scope on errexit.
  # shellcheck disable=SC2064
  trap "$(printf 'chmod -R u+rwX -- %q; rm -rf -- %q' "$fixture" "$fixture")" EXIT
  tar -C "$root" --exclude=.git --exclude=bin --exclude=.fbc-test-sandbox -cf - . | tar -C "$fixture" -xf -
  mkdir -p "$fixture/bin"
  if [ -d "$root/bin" ]; then cp -a "$root/bin/." "$fixture/bin/"; fi
  # The reset baseline is the candidate, never the caller's HEAD.
  git -C "$fixture" init -q
  # Tests commit too (update-bundle's create_commit); CI runners have no identity.
  git -C "$fixture" config user.name FBC-test
  git -C "$fixture" config user.email fbc-test@localhost
  git -C "$fixture" config core.hooksPath /dev/null
  git -C "$fixture" config commit.gpgsign false
  git -C "$fixture" add -f .
  git -C "$fixture" commit -qm candidate
  touch "$fixture/.fbc-test-sandbox"
  FBC_TEST_SANDBOX="$fixture" bash "$fixture/${script#"$root/"}" "${@:2}" || status=$?
  chmod -R u+rwX -- "$fixture"
  rm -rf -- "$fixture"
  trap - EXIT
  exit "$status"
}
isolate_test "$0" "$@"
