#!/usr/bin/env bash
# Build script for kanso engine

OPTIONS=':hx'

# Uncomment for debug
#set -x

# Print args to STDERR
error() {
    local TXT=("$@")
    printf "%s\n" "${TXT[@]}" >&2
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

    exit "$EC"
}

! [[ -d ./src ]] && die 127 \
    "Not on root of repository." \
    "You must execute this script in the root of the repo."

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

    if [[ $# -gt 0 ]] && [[ "$1" =~ ^(0|-?[1-9][0-9]+)$ ]]; then
        EC="$1"
    fi

    local TXT=(
        "build.sh: Kanso build script"
        ""
        "Usage: build.sh [-h|-x]"
        ""
        "        -h                    Prints this help message with exit code 0"
        "        -x                    Cleans the autogenerated code and the output object(s)"
    )

    die "$EC" "${TXT[@]}"
}

__clean_repo() {
    local EC=0

    rm -f ./src/xdg-shell-client-protocol.h ./src/xdg-shell-protocol.c || EC=1
    rm -rf ./bin || EC=1

    die "$EC"
}

while getopts "$OPTIONS" OPTION; do
    case "$OPTION" in
        h) usage 0;;
        x) __clean_repo;;
        *) usage 1;;
    esac
done

# If SDK env not initialized
if [[ -z ${VULKAN_SDK+X} ]]; then
    error "WARNING: Vulkan environment not initialized"
    export VULKAN_SDK='/usr'
fi

if _cmd 'wayland-scanner' && [[ -f /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml ]]; then
    wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
        ./src/xdg-shell-client-protocol.h

    wayland-scanner private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
        ./src/xdg-shell-protocol.c

else
    die 127 "No xdg-shell code available!"
fi

C_FILENAMES=$(find ./src -type f -regex '.*\.c$')
COMPILER_FLAGS=("-std=gnu17" "-g" "-Og" "-fPIC")
# COMPILER_FLAGS+=("-Wall" "-pedantic") # Uncomment if warnings are desired
# COMPILER_FLAGS+=("-Wextra") # Uncomment if extra warnings are desired
# COMPILER_FLAGS+=("-Werror") # Uncomment if errors should terminate compilation
INCLUDE_FLAGS=("-I$VULKAN_SDK/include" "-Isrc")
LINKER_FLAGS=("-L$VULKAN_SDK/lib" "-lvulkan" "-lwayland-client" "-lm" "-shared")
OUT_DIR="bin"

mkdir -p ./"$OUT_DIR"

gcc $C_FILENAMES -o ./"$OUT_DIR"/libkansoengine.so \
    "${COMPILER_FLAGS[@]}" \
    "${INCLUDE_FLAGS[@]}" \
    "${LINKER_FLAGS[@]}" || die 1 "Compilation failed"

# Make sure to kill debugging
#set +x

die 0
