# list recipes
default:
    @just --list

# build build/Tom.app (release, ad-hoc signed)
app:
    ./scripts/build-app.sh

# build and (re)launch
run: app _kill
    open build/Tom.app

# install to ~/Applications and launch (needed for launch at login)
install: app _kill
    rm -rf ~/Applications/Tom.app
    mkdir -p ~/Applications
    cp -R build/Tom.app ~/Applications/Tom.app
    open ~/Applications/Tom.app

# render orb/morph/dissolve test frames to build/vfx
vfx:
    swift build
    .build/debug/Tom --vfx-test build/vfx

# quit a running tom and wait until it's really gone, or `open` fails with -600
_kill:
    #!/usr/bin/env bash
    pkill -x Tom || true
    for _ in $(seq 50); do pgrep -x Tom >/dev/null || exit 0; sleep 0.1; done
    pkill -9 -x Tom || true

# remove build outputs
clean:
    rm -rf .build build
