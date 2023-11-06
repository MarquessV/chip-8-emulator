default:
    zig build test

build:
    zig build

run rom_path scale='20': build
    zig-out/bin/chip-8-emulator {{rom_path}} --scale {{scale}}

run-help: build
    zig-out/bin/chip-8-emulator -h

