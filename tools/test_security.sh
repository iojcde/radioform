#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/radioform-security.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

# Both sides must build against exactly the same protocol and security helpers.
cmp packages/driver/include/RFSharedAudio.h packages/host/Sources/CRadioformAudio/include/RFSharedAudio.h
cmp packages/driver/include/RFSecureIPC.h packages/host/Sources/CRadioformAudio/include/RFSecureIPC.h

clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all -g \
    packages/driver/tests/test_security.c -o "$TEST_DIR/audio-security"
"$TEST_DIR/audio-security"

swiftc -module-cache-path "$TEST_DIR/module-cache" \
    apps/mac/RadioformApp/Sources/Services/DriverInstallCommand.swift \
    apps/mac/RadioformApp/Tests/DriverInstallCommandTests.swift \
    -o "$TEST_DIR/installer-security"
"$TEST_DIR/installer-security"
