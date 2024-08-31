#!/usr/bin/env bash
# Build script for kanso engine

# Uncomment for debug
#set -x

OPTIONS=':hxsvg'

# Option-related
STRIP=0                   # Becomes 1 if `-s` is passed
CLEAN=0                   # Becomes 1 if `-x` is passed
VERBOSE=0                 # Becomes 1 if `-v` is passed
ONLY_GENERATE=0           # Becomes 1 if `-g` is passed

# Project directories
OBJ_DIR="obj"
OUT_DIR="bin"

# Print args to STDERR
error() {
    local TXT=("$@")
    printf "%s\n" "${TXT[@]}" >&2
    return 0
}

verb_error() {
    if [[ $VERBOSE -eq 1 ]] && [[ $# -ge 1 ]]; then
        error "$@"
    fi
    return 0
}

verb_log() {
    if [[ $VERBOSE -eq 1 ]] && [[ $# -ge 1 ]]; then
        local TXT=("$@")
        printf "%s\n" "${TXT[@]}"
    fi

    return 0
}

# Terminate script execution
die() {
    local EC=1

    if [[ $# -ge 1 ]] && [[ $1 =~ ^(0|-?[1-9][0-9]*)$ ]]; then
        EC=$1
        shift
    fi

    if [[ $# -ge 1 ]]; then
        local TXT=("$@")
        if [[ $EC -eq 0 ]]; then
            printf "%s\n" "${TXT[@]}"
        else
            error "${TXT[@]}"
        fi
    fi

    # Make sure to kill debugging
    set +x

    exit "$EC"
}

# Determine if one or more commands exist in shell or not
_cmd() {
    [[ $# -eq 0 ]] && return 127

    local EC=0

    while [[ $# -gt 0 ]]; do
        if ! command -v "$1" &> /dev/null; then
            EC=1
            break
        fi

        shift
    done

    return "$EC"
}

# Print help message
usage() {
    local EC=0

    if [[ $# -ge 1 ]] && [[ $1 =~ ^(0|-?[1-9][0-9]*)$ ]]; then
        EC="$1"
    fi

    local TXT=(
        "build.sh: Kanso build script"
        ""
        "Usage: build.sh -h"
        "       build.sh [-v] -x"
        "       build.sh [-v] -s"
        ""
        "        -h                    Prints this help message with exit code 0"
        "        -v                    Verbose mode"
        "        -x                    Cleans the autogenerated code and the output object(s)"
        "        -s                    Strips the output binaries after compilation"
        ""
    )

    die "$EC" "${TXT[@]}"
}

__autogen() {
    if _cmd 'wayland-scanner' && [[ -f /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml ]]; then
        verb_log "Generating \`src/xdg-shell-client-protocol.h\`..."
        wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
            ./src/xdg-shell-client-protocol.h

        verb_log "Done"

        verb_log "Generating \`src/xdg-shell-protocol.c\`..."
        wayland-scanner private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
            ./src/xdg-shell-protocol.c

        verb_log "Done"
    else
        die 127 "No xdg-shell code available!"
    fi

    return 0
}

__clean_repo() {
    local EC=0
    local RM_COMMAND=""

    if [[ $VERBOSE -eq 1 ]]; then
        RM_COMMAND="rm -rvf"
    else
        RM_COMMAND="rm -rf"
    fi

    verb_log "Cleaning up..."

    eval "$RM_COMMAND src/xdg-shell-client-protocol.h src/xdg-shell-protocol.c bin obj"
    EC=$?

    verb_log "" "Done"

    die "$EC"
}

# If not in root of repository
! [[ -d ./src ]] && die 127 \
    "Not on root of repository." \
    "You must execute this script in the root of the repo."

while getopts "$OPTIONS" OPTION; do
    case "$OPTION" in
        h) usage 0;;
        x) CLEAN=1;;
        s) STRIP=1 ;;
        v) VERBOSE=1 ;;
        g) ONLY_GENERATE=1 ;;
        *) usage 1;;
    esac
done

# If `-x` is passed
[[ $CLEAN -eq 1 ]] && __clean_repo

# If SDK env not initialized
if [[ -z ${VULKAN_SDK+X} ]]; then
    if [[ -f ./setup-env.sh ]];then
        . ./setup-env.sh
    else
        error "WARNING: Vulkan environment not initialized"
        verb_error "Falling back to \`/usr\`"
        export VULKAN_SDK='/usr'
    fi
fi

__autogen

[[ $ONLY_GENERATE -eq 1 ]] && die 0

COMPILER_FLAGS=("-std=gnu17" "-g" "-Og" "-fPIC" "-mtune=generic")
[[ $VERBOSE -eq 1 ]] && COMPILER_FLAGS+=("-Wall" "-pedantic" "-Wno-unused")
# COMPILER_FLAGS+=("-Wextra")                           # Uncomment if extra warnings are desired
# COMPILER_FLAGS+=("-Werror")                           # Uncomment if errors should terminate compilation
INCLUDE_FLAGS=("-I$VULKAN_SDK/include" "-Isrc")
LINKER_FLAGS=("-L$VULKAN_SDK/lib" "-lvulkan" "-lwayland-client" "-lm" "-lc")

mkdir -p "$OBJ_DIR"

# Compile each source file into object file
for F in src/*.c; do
    FILE="$(basename "$F")"

    verb_log "$F ==> ${OBJ_DIR}/${FILE%.c}.o"

    gcc -c src/"$FILE" -o "$OBJ_DIR/${FILE%.c}.o" \
        "${COMPILER_FLAGS[@]}" \
        "${INCLUDE_FLAGS[@]}" || die 1 "Failed to compile \`$F\` into object file"

done

O_FILENAMES=$(find "$OBJ_DIR" -type f -regex '.*\.o$')

mkdir -p "$OUT_DIR"

verb_log "Generating \`libkansoengine.so\`..."

gcc $O_FILENAMES -o "$OUT_DIR"/libkansoengine.so \
    "${COMPILER_FLAGS[@]}" \
    "${INCLUDE_FLAGS[@]}" \
    "${LINKER_FLAGS[@]}" \
    -shared || die 1 "Compilation failed"


verb_log "Done" ""

if [[ $STRIP -eq 1 ]]; then
    verb_log "Stripping \`libkansoengine.so\`..."
    strip "$OUT_DIR"/libkansoengine.so \
        && verb_log "Done" ""

fi

die 0
