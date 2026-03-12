#!/usr/bin/env bash
# LLM Studio build & install helper
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

check_deps() {
    echo "Checking build dependencies..."
    local missing=()

    command -v meson   &>/dev/null || missing+=("meson")
    command -v ninja   &>/dev/null || missing+=("ninja-build")
    command -v valac   &>/dev/null || missing+=("valac (vala)")

    # Check pkg-config packages
    for pkg in gtk4 libadwaita-1 libsoup-3.0 json-glib-1.0 webkitgtk-6.0 libcmark-gfm; do
        pkg-config --exists "$pkg" 2>/dev/null || missing+=("$pkg dev package")
    done

    # cmark-gfm-extensions has no .pc file — check for the header directly
    [ -f /usr/include/cmark-gfm-core-extensions.h ] || missing+=("libcmark-gfm-extensions-dev")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  • $dep"
        done
        echo ""
        echo "On Ubuntu/Debian:"
        echo "  sudo apt install meson ninja-build valac \\"
        echo "    libgtk-4-dev libadwaita-1-dev \\"
        echo "    libsoup-3.0-dev libjson-glib-dev \\"
        echo "    libwebkitgtk-6.0-dev libcmark-gfm-dev libcmark-gfm-extensions-dev libjs-katex fonts-katex"
        echo ""
        echo "On Fedora:"
        echo "  sudo dnf install meson ninja-build vala \\"
        echo "    gtk4-devel libadwaita-devel \\"
        echo "    libsoup-devel json-glib-devel"
        echo ""
        echo "On Arch:"
        echo "  sudo pacman -S meson ninja vala \\"
        echo "    gtk4 libadwaita libsoup json-glib"
        exit 1
    fi
    echo "All dependencies found."
}

configure() {
    echo "Configuring build..."
    meson setup "$BUILD_DIR" "$SCRIPT_DIR" \
        --prefix=/usr \
        --buildtype=debugoptimized \
        -Db_sanitize=none
}

build() {
    echo "Building..."
    ninja -C "$BUILD_DIR"
}

install_app() {
    echo "Installing (may require sudo)..."
    sudo ninja -C "$BUILD_DIR" install
    sudo glib-compile-schemas /usr/share/glib-2.0/schemas/
    echo "Installation complete. Run: llm-studio"
}

run_local() {
    echo "Running without installing..."
    # Install schema to user dir
    local schema_dir="$HOME/.local/share/glib-2.0/schemas"
    mkdir -p "$schema_dir"
    cp "$SCRIPT_DIR/data/dev.llmstudio.LLMStudio.gschema.xml" "$schema_dir/"
    glib-compile-schemas "$schema_dir"
    GSETTINGS_SCHEMA_DIR="$schema_dir" "$BUILD_DIR/src/llm-studio"
}

case "${1:-}" in
    check)     check_deps ;;
    configure) check_deps && configure ;;
    build)     build ;;
    install)   check_deps && configure && build && install_app ;;
    run)       check_deps && configure && build && run_local ;;
    clean)     rm -rf "$BUILD_DIR" && echo "Cleaned." ;;
    *)
        echo "LLM Studio build script"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  check      - Check build dependencies"
        echo "  configure  - Configure the build system"
        echo "  build      - Build the application"
        echo "  install    - Full build and system install"
        echo "  run        - Build and run without installing"
        echo "  clean      - Remove build directory"
        ;;
esac
