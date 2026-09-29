#!/bin/bash
# Exercise publication, where a signal can arrive between either rename.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/"{build,scripts,bin,commands,catalog-4-22}
# make -C and Python subprocess(cwd=...) must resolve tools inside the target.
make --no-print-directory -C "$fixture" -f "$PWD/Makefile" \
  --eval 'check-local-bin: ; @test "$(LOCAL_BIN)" = "$(CURDIR)/bin"' check-local-bin
cp build/build.sh "$fixture/build/"
echo original > "$fixture/catalog-4-22/value"
echo input > "$fixture/catalog-template.yaml"
echo '{"4.22":"0.23","5.0":"0.23"}' > "$fixture/drop-versions.json"
for script in generate-catalog-template format-yaml; do
  printf '#!/bin/bash\nexit 0\n' > "$fixture/scripts/$script.sh"
done
cat > "$fixture/scripts/render-catalog.sh" <<'SCRIPT'
#!/bin/bash
mkdir catalog-4-22 catalog-5-0
echo replacement > catalog-4-22/value
echo new > catalog-5-0/value
SCRIPT
printf '#!/bin/bash\nexit 0\n' > "$fixture/bin/opm"
real_mv=$(command -v mv)
export real_mv
cat > "$fixture/commands/mv" <<'SCRIPT'
#!/bin/bash
case "$FAULT:$2" in
  signal:*/previous-4-22)
    "$real_mv" "$@"
    kill -TERM "$PPID"
    exit 0 ;;
  failure:*/catalog-5-0) exit 1 ;;
esac
exec "$real_mv" "$@"
SCRIPT
chmod +x "$fixture/scripts/"* "$fixture/bin/opm" "$fixture/commands/mv"
for FAULT in signal failure; do
  export FAULT
  if PATH="$fixture/commands:$PATH" "$fixture/build/build.sh"; then
    echo "Publication ignored $FAULT" >&2
    exit 1
  fi
  test "$(cat "$fixture/catalog-4-22/value")" = original
  test "$(cat "$fixture/catalog-template.yaml")" = input
  test ! -e "$fixture/catalog-5-0"
  test ! -e "$fixture/.catalog-build.lock"
done
unset FAULT
"$fixture/build/build.sh"
test "$(cat "$fixture/catalog-4-22/value")" = replacement
test "$(cat "$fixture/catalog-5-0/value")" = new
test "$(cat "$fixture/catalog-template.yaml")" = input
echo 'Catalog publication rollback regressions passed'
