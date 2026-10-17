#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/radioform-features.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path "$TEST_DIR/module-cache" \
    apps/mac/RadioformApp/Sources/Models/EQBand.swift \
    apps/mac/RadioformApp/Sources/Models/EQPreset.swift \
    apps/mac/RadioformApp/Sources/Services/AutoEQCodec.swift \
    apps/mac/RadioformApp/Tests/AutoEQTests.swift -o "$TEST_DIR/autoeq-tests"
"$TEST_DIR/autoeq-tests"

swiftc -module-cache-path "$TEST_DIR/module-cache" \
    apps/mac/RadioformApp/Sources/Models/EQBand.swift \
    apps/mac/RadioformApp/Sources/Models/EQPreset.swift \
    apps/mac/RadioformApp/Sources/Services/AutoEQCodec.swift \
    apps/mac/RadioformApp/Sources/Services/PresetManager.swift \
    apps/mac/RadioformApp/Tests/PresetManagerTests.swift -o "$TEST_DIR/preset-manager-tests"
"$TEST_DIR/preset-manager-tests"

# Build a matching DSP archive so the app-to-host capacity test cannot link an
# older ten-band binary against the expanded C preset structure.
cmake -S packages/dsp -B "$TEST_DIR/dsp-build" \
    -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
    -DBUILD_TESTS=ON -DBUILD_BRIDGE=OFF -DBUILD_TOOLS=OFF
cmake --build "$TEST_DIR/dsp-build" -j 4
ctest --test-dir "$TEST_DIR/dsp-build" --output-on-failure
swiftc -module-cache-path "$TEST_DIR/module-cache" \
    -I packages/host/Sources/CRadioformDSP/include \
    apps/mac/RadioformApp/Sources/Models/EQBand.swift \
    apps/mac/RadioformApp/Sources/Models/EQPreset.swift \
    apps/mac/RadioformApp/Sources/Services/AutoEQCodec.swift \
    packages/host/Sources/RadioformHost/Presets/PresetLoader.swift \
    packages/host/Tests/ExtendedPresetTests.swift \
    "$TEST_DIR/dsp-build/libradioform_dsp.a" -lc++ -framework Accelerate \
    -o "$TEST_DIR/extended-preset-tests"
"$TEST_DIR/extended-preset-tests"

swiftc -module-cache-path "$TEST_DIR/module-cache" \
    -I packages/host/Sources/CRadioformDSP/include \
    packages/host/Sources/RadioformHost/Audio/DSPProcessor.swift \
    packages/host/Tests/DSPProcessorTests.swift \
    "$TEST_DIR/dsp-build/libradioform_dsp.a" -lc++ -framework Accelerate \
    -o "$TEST_DIR/dsp-processor-tests"
"$TEST_DIR/dsp-processor-tests"

swiftc -module-cache-path "$TEST_DIR/module-cache" -emit-library -emit-module \
    -module-name RadioformConfiguration packages/configuration/Sources/RadioformConfiguration/*.swift \
    -emit-module-path "$TEST_DIR/RadioformConfiguration.swiftmodule" \
    -o "$TEST_DIR/libRadioformConfiguration.dylib"
swiftc -module-cache-path "$TEST_DIR/module-cache" -I "$TEST_DIR" \
    -I packages/host/Sources/CRadioformAudio/include -L "$TEST_DIR" -lRadioformConfiguration \
    -Xlinker -rpath -Xlinker "$TEST_DIR" \
    packages/host/Sources/RadioformHost/Devices/DeviceRegistry.swift \
    packages/host/Tests/OutputSelectionTests.swift -o "$TEST_DIR/output-selection-tests"
"$TEST_DIR/output-selection-tests"

swift test --package-path packages/configuration --scratch-path "$TEST_DIR/configuration-build" \
    --disable-keychain --disable-netrc --disable-sandbox \
    -Xswiftc -module-cache-path -Xswiftc "$TEST_DIR/module-cache"
