#!/usr/bin/env bash
# Inject MagicLoader into Minecraft (Bedrock on Linux) as soon as the game starts,
# then, optionally, client DLLs once the main menu is up.
# BOL's own injector waits for the main menu, by which time the game has made
# the camera buffers, block atlas and render targets MagicLoader has to see created.
# Clients are the other way round: injected mid-startup some of them misbehave,
# so they wait for the menu, as BOL's auto-inject does.
#
# Usage: turn OFF auto-inject in BOL, start this, then press PLAY in BOL.
#   ./magic-early-inject.sh [client.dll ...]
#
# Overrides (environment): BOL_HOME, BOL_PREFIX, BOL_ENGINE, MAGIC_DLL,
#   MAGIC_DELAY  seconds after the game process appears before MagicLoader goes in (default 1)
#   CLIENT_DELAY seconds after the main menu is up before the clients go in (default 3)
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
MAGIC_DELAY="${MAGIC_DELAY:-1}"
CLIENT_DELAY="${CLIENT_DELAY:-3}"
MENU_CEILING=150
LOG="$B/logs/early-inject.log"

for f in "$ENGINE/files/bin/wine" "$INJECTOR"; do
    [ -e "$f" ] || { echo "Not found: $f"; [ "$f" = "$INJECTOR" ] && echo "Use BOL's 'Inject DLL' once so it unpacks injector.exe."; exit 1; }
done
CLIENTS=()
for c in "$@"; do
    [ -f "$c" ] || { echo "Client DLL not found: $c"; exit 1; }
    # Wine sees a host /a/b.dll as Z:\a\b.dll.
    CLIENTS+=("Z:$(realpath "$c" | tr / '\\')")
done
mkdir -p "$B/logs"

# Only the injector gets the Wine environment: BOL treats any process carrying
# this WINEPREFIX as "still using the prefix" and refuses to launch.
LIBS="$ENGINE/files/lib/x86_64-linux-gnu:$ENGINE/files/lib/aarch64-linux-gnu:$ENGINE/files/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
inject() {
    env WINEPREFIX="$PREFIX" WINEESYNC=1 WINEFSYNC=1 WINEDEBUG=-all \
        LD_LIBRARY_PATH="$LIBS" \
        "$ENGINE/files/bin/wine" "$INJECTOR" "$1" Minecraft.Windows.exe
}

game_running() { ps -eo args= | grep -q '\\Minecraft\.Windows\.exe'; }

# The game writes these right after it draws its main menu (BOL's auto-inject
# uses the same signal).
menu_reached() {
    local home data marker t
    for home in "$PREFIX"/drive_c/users/*/; do
        for data in "Minecraft Bedrock" "Minecraft Bedrock Preview"; do
            for marker in "Flighting/currentTreatments" "bootstrapStorage/bootstrap_settings.json"; do
                t=$(stat -c %Y "$home/AppData/Roaming/$data/$marker" 2>/dev/null) || continue
                [ "$t" -ge "$SINCE" ] && return 0
            done
        done
    done
    return 1
}

if game_running; then
    echo "Minecraft is already running. Close it first, then start this before PLAY."
    exit 1
fi

SINCE=$(date +%s)
echo "Waiting for Minecraft to start (press PLAY in BOL)..."
until game_running; do sleep 0.1; done
echo "Game process seen; injecting MagicLoader in ${MAGIC_DELAY}s."
sleep "$MAGIC_DELAY"

injected=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    {
        echo "--- early inject attempt $attempt $(date +%T) ---"
        inject "$DLL"
    } >>"$LOG" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "MagicLoader injected on attempt $attempt."
        injected=1
        break
    fi
    echo "Attempt $attempt failed (code $rc), retrying..."
    game_running || { echo "Minecraft exited."; exit 1; }
    sleep 0.5
done
[ "$injected" -eq 1 ] || { echo "Gave up on MagicLoader; see $LOG"; exit 1; }

[ "${#CLIENTS[@]}" -gt 0 ] || exit 0

echo "Waiting for the main menu before injecting ${#CLIENTS[@]} client DLL(s)..."
waited=0
until menu_reached; do
    game_running || { echo "Minecraft exited."; exit 1; }
    if [ "$waited" -ge $((MENU_CEILING * 4)) ]; then
        echo "The game never said its menu was up; injecting anyway."
        break
    fi
    sleep 0.25
    waited=$((waited + 1))
done
sleep "$CLIENT_DELAY"

status=0
for c in "${CLIENTS[@]}"; do
    game_running || { echo "Minecraft exited."; exit 1; }
    {
        echo "--- client inject $c $(date +%T) ---"
        inject "$c"
    } >>"$LOG" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "Injected $c"
    else
        echo "Failed to inject $c (code $rc); see $LOG"
        status=1
    fi
    sleep 1
done
exit "$status"
