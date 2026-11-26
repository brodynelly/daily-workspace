# Daily Workspace tasks. `just` lists them.

default:
    @just --list

# Install or update the app in /Applications: checks, release build, backup, install, launch, Start at Login
run:
    scripts/install_app.sh

# Same as run, but skip build/test/lint
quick:
    scripts/install_app.sh --skip-checks

# Install/update without launching
install:
    scripts/install_app.sh --no-launch

# Build, bundle and launch the debug app from ./build
dev:
    ./scripts/build_and_run.sh --verify

# Build, test and lint (the baseline recipes)
check:
    swift build
    swift test
    swift format lint --strict --recursive Sources Tests Package.swift
    swiftlint --strict

# Format sources in place
fmt:
    swift format --in-place --recursive Sources Tests Package.swift

# Show app, CLI and login-item status
status:
    ~/.local/bin/daily status
    ~/.local/bin/daily login status

# Stream the app's logs
logs:
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.dailyworkspace.mac"'

# List install backups, newest first
backups:
    @ls -1t ~/.config/daily-workspace/backups 2>/dev/null || echo "no backups"
