#!/usr/bin/env bash
# Report the gap between what's installed and what lib/manifest.sh declares.
#
#   bash capture/packages.sh                 # report
#   bash capture/packages.sh --add gh fd-find    # add to APT_PACKAGES
#   bash capture/packages.sh --add-snap dbeaver-ce
#   bash capture/packages.sh --ignore evtest      # hide it from future reports
#
# This one reports rather than captures, and that is deliberate. The other
# capture scripts can tell what belongs in the repo; this one cannot. Of the 132
# manually-installed packages here, most are Ubuntu's own and a handful are
# things you chose — and only you know which. Auto-adding all of them would turn
# lib/manifest.sh into a list nobody trusts, which is worse than it being short.
#
# The gap matters: a package installed by hand and never declared is the main
# reason a rebuilt machine comes out quietly different from this one.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES/capture/common.sh"
# shellcheck source=/dev/null
source "$DOTFILES/lib/manifest.sh"

export LC_ALL=C
IGNORE_FILE="$DOTFILES/capture/packages-ignore.txt"
MANIFEST="$DOTFILES/lib/manifest.sh"

# ─── flags that take arguments ────────────────────────────────────────────────
MODE=report
declare -a TARGETS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --add)       MODE=add;      shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do TARGETS+=("$1"); shift; done ;;
        --add-snap)  MODE=add-snap; shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do TARGETS+=("$1"); shift; done ;;
        --ignore)    MODE=ignore;   shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do TARGETS+=("$1"); shift; done ;;
        *) shift ;;
    esac
done

# Insert names into a bash array in manifest.sh, just before its closing paren.
add_to_array() {
    local array="$1"; shift
    local added=0
    for pkg in "$@"; do
        if grep -qE "^\s+${pkg}\s*$" "$MANIFEST"; then
            warn "Already declared: $pkg"
            continue
        fi
        # awk rather than sed: needs to find the closing ) of one named array
        # rather than the first ) in the file.
        awk -v arr="$array" -v pkg="$pkg" '
            $0 ~ "^"arr"=\\(" { inside=1 }
            inside && /^\)/    { print "    " pkg; inside=0 }
            { print }
        ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
        info "Added to $array: $pkg"
        added=$((added + 1)); captured
    done
    [ "$added" -eq 0 ] && info "Nothing added"
}

case "$MODE" in
    add)
        [ "${#TARGETS[@]}" -gt 0 ] || { warn "--add needs at least one package"; exit 1; }
        section "Adding to APT_PACKAGES"
        add_to_array APT_PACKAGES "${TARGETS[@]}"
        capture_summary; exit 0 ;;
    add-snap)
        [ "${#TARGETS[@]}" -gt 0 ] || { warn "--add-snap needs at least one package"; exit 1; }
        section "Adding to SNAP_PACKAGES"
        add_to_array SNAP_PACKAGES "${TARGETS[@]}"
        capture_summary; exit 0 ;;
    ignore)
        [ "${#TARGETS[@]}" -gt 0 ] || { warn "--ignore needs at least one pattern"; exit 1; }
        section "Ignoring"
        for pat in "${TARGETS[@]}"; do
            printf '%s\n' "$pat" >> "$IGNORE_FILE"
            info "Ignoring: $pat"; captured
        done
        capture_summary; exit 0 ;;
esac

# ─── report ───────────────────────────────────────────────────────────────────
section "Comparing installed packages against lib/manifest.sh"

is_ignored() {
    local pkg="$1" pat
    while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        case "$pat" in \#*) continue ;; esac
        # shellcheck disable=SC2254
        case "$pkg" in $pat) return 0 ;; esac
    done < "$IGNORE_FILE"
    return 1
}

apt-mark showmanual 2>/dev/null | sort -u > /tmp/capture-apt-live.txt
# The .debs install through dpkg, so apt-mark counts them as manual too: declare
# them here or they show up as undeclared.
printf '%s\n' "${APT_PACKAGES[@]}" "${APT_BUILD_PACKAGES[@]}" \
    obsidian "${DEB_PACKAGES[@]%%|*}" | sort -u > /tmp/capture-apt-repo.txt

echo
echo "  Declared but NOT installed — a rebuild expects these:"
missing=0
while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    echo "    $pkg"; missing=$((missing + 1))
done < <(comm -13 /tmp/capture-apt-live.txt /tmp/capture-apt-repo.txt)
[ "$missing" -eq 0 ] && echo "    (none)"

echo
echo "  Installed but NOT declared — a rebuild would not have these:"
undeclared=0
while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    is_ignored "$pkg" && continue
    echo "    $pkg"; undeclared=$((undeclared + 1))
done < <(comm -23 /tmp/capture-apt-live.txt /tmp/capture-apt-repo.txt)
[ "$undeclared" -eq 0 ] && echo "    (none)"

echo
echo "  Snaps installed but NOT declared:"
snap list 2>/dev/null | tail -n +2 | awk '{print $1}' | sort -u > /tmp/capture-snap-live.txt
printf '%s\n' "${SNAP_PACKAGES[@]}" | cut -d: -f1 | sort -u > /tmp/capture-snap-repo.txt
snaps=0
while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    is_ignored "$pkg" && continue
    echo "    $pkg"; snaps=$((snaps + 1))
done < <(comm -23 /tmp/capture-snap-live.txt /tmp/capture-snap-repo.txt)
[ "$snaps" -eq 0 ] && echo "    (none)"

rm -f /tmp/capture-apt-live.txt /tmp/capture-apt-repo.txt \
      /tmp/capture-snap-live.txt /tmp/capture-snap-repo.txt

echo
if [ "$undeclared" -gt 0 ] || [ "$snaps" -gt 0 ]; then
    info "Record one with:  bash capture/packages.sh --add <pkg>"
    info "Or hide it with:  bash capture/packages.sh --ignore <pkg>"
else
    info "Nothing undeclared — the manifest matches this machine."
fi
[ "$missing" -gt 0 ] && warn "$missing declared package(s) are not installed — run install.sh, or drop them from the manifest"
exit 0
