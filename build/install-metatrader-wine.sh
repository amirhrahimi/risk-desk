#!/usr/bin/env bash
# Risk Desk - installs MetaTrader 4 and 5 into a Wine prefix on Linux, the way CI builds
# Risk Desk (.github/workflows/build.yml, ADR-033). Also usable to set up a Linux machine for
# development (ADR-032).
#
#   bash build/install-metatrader-wine.sh [--install-wine] [--prefix DIR] [--paths-file FILE]
#                                         [--wine-version VERSION] [--platforms "mt4 mt5"]
#
#   --install-wine   first install Wine from WineHQ (development branch, VERSION pinned) and
#                    Xvfb with apt. Debian and Ubuntu only; needs root or sudo.
#   --prefix         the Wine prefix to create or update. Default ~/.wine-riskdesk.
#   --paths-file     write a paths file for build.ps1 (-PathsFile): the MetaEditor paths and,
#                    for each terminal that has been started once (its MQL4 / MQL5 folder
#                    exists), a $Terminals entry. Refuses to overwrite an existing file.
#   --wine-version   WineHQ development version for --install-wine. Default 11.21, the version
#                    with which MetaTrader passed its anti-debugging check (ADR-032).
#   --platforms      which terminals to install. Default "mt4 mt5".
#
# The prefix is set to Windows 11: with Wine 11.21, MetaTrader's anti-debugging check
# ("A debugger has been found running in your system") passes only with that profile.
# Wine's Mono and Gecko are switched off, so no install prompt waits for a click.
# Without a DISPLAY the script runs its own Xvfb.
set -euo pipefail

PREFIX="$HOME/.wine-riskdesk"
WINE_VERSION="11.21"
INSTALL_WINE=0
PATHS_FILE=""
PLATFORMS="mt4 mt5"

die() { echo "FAIL  $*" >&2; exit 1; }
info() { echo "INFO  $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --install-wine) INSTALL_WINE=1 ;;
        --prefix) PREFIX="$2"; shift ;;
        --paths-file) PATHS_FILE="$2"; shift ;;
        --wine-version) WINE_VERSION="$2"; shift ;;
        --platforms) PLATFORMS="$2"; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) die "unknown argument $1 (see --help)" ;;
    esac
    shift
done
[ "$(uname -s)" = Linux ] || die "Linux only. On macOS use MetaQuotes' MetaTrader app (CONTRIBUTING.md)."
if [ -n "$PATHS_FILE" ] && [ -e "$PATHS_FILE" ]; then die "$PATHS_FILE exists; remove it or choose another --paths-file"; fi

#--- Wine from WineHQ ---------------------------------------------------------------------------
if [ "$INSTALL_WINE" = 1 ]; then
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
    . /etc/os-release
    case "${ID:-}" in ubuntu|debian) ;; *) die "--install-wine supports Debian and Ubuntu (this is ${ID:-unknown}); install Wine $WINE_VERSION yourself" ;; esac
    codename="${VERSION_CODENAME:?no VERSION_CODENAME in /etc/os-release}"
    version="${WINE_VERSION}~${codename}-1"
    info "installing WineHQ $version (devel) and Xvfb"
    $SUDO dpkg --add-architecture i386
    $SUDO mkdir -pm755 /etc/apt/keyrings
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/winehq-archive.key
    $SUDO curl -fsSL -o "/etc/apt/sources.list.d/winehq-$codename.sources" \
        "https://dl.winehq.org/wine-builds/$ID/dists/$codename/winehq-$codename.sources"
    $SUDO apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --install-recommends \
        "winehq-devel=$version" "wine-devel=$version" "wine-devel-amd64=$version" "wine-devel-i386:i386=$version" \
        xvfb xauth >/dev/null \
        || die "apt could not install WineHQ $version: is it still offered for $codename? (apt-cache madison winehq-devel)"
fi
command -v wine >/dev/null || die "wine not found: install it, or run with --install-wine"
info "$(wine --version) from $(command -v wine)"

#--- display ------------------------------------------------------------------------------------
XVFB_PID=""
cleanup() {
    WINEPREFIX="$PREFIX" wineserver -k >/dev/null 2>&1 || true
    if [ -n "$XVFB_PID" ]; then kill "$XVFB_PID" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
if [ -z "${DISPLAY:-}" ]; then
    command -v Xvfb >/dev/null || die "no DISPLAY and no Xvfb: install xvfb (or run with --install-wine)"
    for n in $(seq 90 120); do
        if [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ]; then display=":$n"; break; fi
    done
    Xvfb "${display:?no free display number}" -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!
    export DISPLAY="$display"
    sleep 2
fi

#--- prefix -------------------------------------------------------------------------------------
export WINEPREFIX="$PREFIX"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="mscoree=;mshtml="   # no Mono / Gecko: MetaTrader needs neither
info "prefix $WINEPREFIX"
timeout 600 wineboot -u >/dev/null 2>&1 || die "wineboot failed for $WINEPREFIX"
wineserver -w
wine winecfg -v win11 >/dev/null 2>&1 || die "winecfg -v win11 failed"
wineserver -w

#--- MetaTrader ---------------------------------------------------------------------------------
tmp="$(mktemp -d)"
for p in $PLATFORMS; do
    case "$p" in
        mt4) folder="MetaTrader 4"; editor="metaeditor.exe" ;;
        mt5) folder="MetaTrader 5"; editor="metaeditor64.exe" ;;
        *) die "unknown platform $p (mt4 or mt5)" ;;
    esac
    found="$(find "$WINEPREFIX/drive_c" -maxdepth 4 -type f -ipath "*/$folder/$editor" 2>/dev/null | head -n 1)"
    if [ -n "$found" ]; then info "$p already installed: $found"; continue; fi
    url="https://download.mql5.com/cdn/web/metaquotes.software.corp/$p/${p}setup.exe"
    info "$p: downloading ${p}setup.exe"
    curl -fsSL -o "$tmp/${p}setup.exe" "$url" || die "download failed: $url"
    info "$p: installing (setup /auto)"
    # the installer may exit non-zero although it installed; the files decide
    timeout 900 wine "$tmp/${p}setup.exe" /auto >/dev/null 2>&1 || info "$p: setup exit code $?"
    sleep 5
    wineserver -k >/dev/null 2>&1 || true   # a terminal the installer started
    wineserver -w
    found="$(find "$WINEPREFIX/drive_c" -maxdepth 4 -type f -ipath "*/$folder/$editor" 2>/dev/null | head -n 1)"
    [ -n "$found" ] || die "$p: $editor not found under $WINEPREFIX/drive_c after the installer"
    info "$p installed: $found"
done
rm -rf "$tmp"

#--- paths file for build.ps1 --------------------------------------------------------------------
if [ -n "$PATHS_FILE" ]; then
    me4="$(find "$WINEPREFIX/drive_c" -maxdepth 4 -type f -ipath '*/MetaTrader 4/metaeditor.exe' 2>/dev/null | head -n 1)"
    me5="$(find "$WINEPREFIX/drive_c" -maxdepth 4 -type f -ipath '*/MetaTrader 5/metaeditor64.exe' 2>/dev/null | head -n 1)"
    {
        echo "# Written by build/install-metatrader-wine.sh for build.ps1 -PathsFile (see build/paths.example.ps1)."
        echo "\$MetaEditor4 = '$me4'"
        echo "\$MetaEditor5 = '$me5'"
        echo "\$Terminals = @("
        # a terminal keeps its data in its install folder under Wine; MQLx appears at its first start
        if [ -n "$me4" ] && [ -d "$(dirname "$me4")/MQL4" ]; then
            echo "    @{ Name = 'MT4 (Wine)'; Platform = 'mt4'; DataPath = '$(dirname "$me4")' }"
        fi
        if [ -n "$me5" ] && [ -d "$(dirname "$me5")/MQL5" ]; then
            echo "    @{ Name = 'MT5 (Wine)'; Platform = 'mt5'; DataPath = '$(dirname "$me5")' }"
        fi
        echo ")"
    } > "$PATHS_FILE"
    info "wrote $PATHS_FILE"
fi
echo "OK    MetaTrader under Wine in $WINEPREFIX"
