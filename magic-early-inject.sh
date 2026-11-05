#!/usr/bin/env bash
# Inject MagicLoader into Minecraft (Bedrock on Linux) as soon as the game starts.
# BOL's own injector waits for the main menu, by which time the game has made
# the camera buffers, block atlas and render targets MagicLoader has to see created.
#
# Usage: turn OFF auto-inject in BOL, start this, then press PLAY in BOL.
#   ./magic-early-inject.sh [seconds to wait after the game process appears, default 1]
#
# Overrides (environment): BOL_HOME, BOL_PREFIX, BOL_ENGINE, MAGIC_DLL
set -u

if [ -n "${BOL_HOME:-}" ]; then
    B="$BOL_HOME"
elif [ -s "${XDG_CONFIG_HOME:-$HOME/.config}/bedrock-on-linux/install_location" ]; then
    B="$(head -n1 "${XDG_CONFIG_HOME:-$HOME/.config}/bedrock-on-linux/install_location")"
else
    B="${XDG_DATA_HOME:-$HOME/.local/share}/bedrock-on-linux"
fi
PREFIX="${BOL_PREFIX:-$B/compatdata/pfx}"
ENGINE="${BOL_ENGINE:-$B/proton/GDK-Proton-xuser}"
INJECTOR="$B/cache/injector.exe"
DLL="${MAGIC_DLL:-C:\\users\\steamuser\\AppData\\Local\\Programs\\MagicLoader\\magic_windows.dll}"
DELAY="${1:-1}"
LOG="$B/logs/early-inject.log"

for f in "$ENGINE/files/bin/wine" "$INJECTOR"; do
    [ -e "$f" ] || { echo "Not found: $f"; [ "$f" = "$INJECTOR" ] && echo "Use BOL's 'Inject DLL' once so it unpacks injector.exe."; exit 1; }
done
mkdir -p "$B/logs"

# Only the injector gets the Wine environment: BOL treats any process carrying
# this WINEPREFIX as "still using the prefix" and refuses to launch.
LIBS="$ENGINE/files/lib/x86_64-linux-gnu:$ENGINE/files/lib/aarch64-linux-gnu:$ENGINE/files/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
inject() {
    env WINEPREFIX="$PREFIX" WINEESYNC=1 WINEFSYNC=1 WINEDEBUG=-all \
        LD_LIBRARY_PATH="$LIBS" \
        "$ENGINE/files/bin/wine" "$INJECTOR" "$DLL" Minecraft.Windows.exe
}

game_running() { ps -eo args= | grep -q '\\Minecraft\.Windows\.exe'; }

if game_running; then
    echo "Minecraft is already running. Close it first, then start this before PLAY."
    exit 1
fi

echo "Waiting for Minecraft to start (press PLAY in BOL)..."
until game_running; do sleep 0.1; done
echo "Game process seen; injecting in ${DELAY}s."
sleep "$DELAY"

for attempt in 1 2 3 4 5 6 7 8 9 10; do
    {
        echo "--- early inject attempt $attempt $(date +%T) ---"
        inject
    } >>"$LOG" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "Injected on attempt $attempt."
        exit 0
    fi
    echo "Attempt $attempt failed (code $rc), retrying..."
    game_running || { echo "Minecraft exited."; exit 1; }
    sleep 0.5
done
echo "Gave up; see $LOG"
exit 1
