#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mkdir -p "$repo_root/work"
test_dir=$(mktemp -d "$repo_root/work/process-control-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
clang -Wall -Wextra -Werror -I "$repo_root/Sources/CTawl/include" \
    "$repo_root/Tests/Native/process_ancestry_test.c" -o "$test_dir/process_ancestry_test"
"$test_dir/process_ancestry_test"
mkdir -p "$test_dir/Tawl Fixture.app/Contents/MacOS" "$test_dir/Postgres Fixture.app/Contents/MacOS"
clang -Wall -Wextra -Werror "$repo_root/Tests/Native/process_control_fixture.c" -o "$test_dir/Tawl Fixture.app/Contents/MacOS/fixture"
cp "$test_dir/Tawl Fixture.app/Contents/MacOS/fixture" "$test_dir/fixture"
cp "$test_dir/Tawl Fixture.app/Contents/MacOS/fixture" "$test_dir/Postgres Fixture.app/Contents/MacOS/fixture"
clang -Wall -Wextra -Werror -I "$repo_root/Sources/CTawl/include" \
    "$repo_root/Sources/CTawl/process_control.c" "$repo_root/Tests/Native/process_control_test.c" -o "$test_dir/process_control_test"
"$test_dir/process_control_test" "$test_dir/Tawl Fixture.app/Contents/MacOS/fixture" \
    "$test_dir/fixture" "$test_dir/Postgres Fixture.app/Contents/MacOS/fixture"
