#!/bin/bash
#
# Build, sign, notarize and package Asciiquarium.saver.
#
#   scripts/release.sh [--dry-run] <version>
#   scripts/release.sh [--dry-run] --staple-only <version>
#
# Produces build/Asciiquarium-<version>.zip containing the signed, notarized, stapled
# Asciiquarium.saver. Maintainer-only: it needs a "Developer ID Application" identity in the
# keychain and a notarytool keychain profile named "asciiquarium-notary" (see README.md).
#
# --dry-run prints every command it would run and runs none of the build, signing or Apple steps.
# The read-only preflight checks still run; a missing identity is reported but does not stop a
# dry run, so the printed plan can be reviewed on any machine.
#
# --staple-only skips the build and the submission. Use it when notarization was Accepted but
# stapling failed (Apple's ticket can take a minute or two to become available): it staples the
# existing build/Build/Products/Release/Asciiquarium.saver, checks it and re-zips it.
#
# Credentials never appear here: notarytool reads them from the keychain profile.
# Deliberately no "set -x", which would echo expanded commands.

set -euo pipefail

NOTARY_PROFILE="asciiquarium-notary"
SCHEME="Asciiquarium"
PRODUCT="Asciiquarium.saver"
BUILD_DIR="build"
PRODUCTS_DIR="$BUILD_DIR/Build/Products/Release"
STAPLE_TRIES=5
STAPLE_DELAY="${STAPLE_RETRY_DELAY:-15}" # seconds between tries; overridable only for tests

DRY_RUN=0
STAPLE_ONLY=0
VERSION=""

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    echo "usage: scripts/release.sh [--dry-run] [--staple-only] <version>   (for example 1.0.0)" >&2
    exit 2
}

# Print a command, then run it unless this is a dry run.
run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

step() {
    echo
    echo "==> $*"
}

# extract_json RAW OUT: copy the JSON object from notarytool's output into OUT, tolerating
# non-JSON lines around it. Tries the last line that starts with "{" on its own (compact
# output), then that line through the end of the file, then through the first closing brace in
# column 0 (pretty-printed output). Succeeds only if plutil can parse the result.
extract_json() {
    local raw="$1" out="$2" start
    grep '^{' "$raw" | tail -n 1 > "$out" || true
    if [ -s "$out" ] && plutil -extract status raw -o - "$out" > /dev/null 2>&1; then
        return 0
    fi
    start="$(grep -n '^{' "$raw" | tail -n 1 | cut -d: -f1 || true)"
    [ -n "$start" ] || return 1
    tail -n +"$start" "$raw" > "$out"
    if plutil -extract status raw -o - "$out" > /dev/null 2>&1; then
        return 0
    fi
    # Pretty-printed object followed by stray lines: stop at the first closing brace in column 0.
    tail -n +"$start" "$raw" | awk '{ print } /^}/ { exit }' > "$out"
    plutil -extract status raw -o - "$out" > /dev/null 2>&1
}

# Scratch files for notarize_zip (globals so the EXIT trap can remove them).
raw=""
json=""

# notarize_zip ZIP: submit to Apple, wait, and return only when the status is Accepted. On any
# failure, fetch Apple's log for the submission (when its id can be found) and die.
notarize_zip() {
    local zip="$1" status="" id="" rc=0
    raw="$(mktemp -t asciiquarium-notary)"
    json="$(mktemp -t asciiquarium-notary-json)"
    trap 'rm -f "$raw" "$json"' EXIT

    echo "+ xcrun notarytool submit $zip --keychain-profile $NOTARY_PROFILE --wait --output-format json"
    # Only stdout is captured (it carries the JSON); stderr stays on the terminal.
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait \
        --output-format json > "$raw" || rc=$?

    if extract_json "$raw" "$json"; then
        status="$(plutil -extract status raw -o - "$json" 2> /dev/null || true)"
        id="$(plutil -extract id raw -o - "$json" 2> /dev/null || true)"
    fi
    if [ -z "$id" ]; then
        # Last resort when the output is not parseable JSON: look for a UUID after "id".
        id="$(grep -Eo '"id"[[:space:]]*:[[:space:]]*"[0-9A-Fa-f-]{36}"' "$raw" | head -n 1 \
            | grep -Eo '[0-9A-Fa-f-]{36}' || true)"
    fi

    if [ "$rc" -eq 0 ] && [ "$status" = "Accepted" ]; then
        echo "submission ${id:-unknown}: status Accepted"
        return 0
    fi

    echo "--- notarytool output ---" >&2
    cat "$raw" >&2
    if [ -n "$id" ]; then
        echo "--- notarization log for submission $id ---" >&2
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 \
            || echo "(could not fetch the log)" >&2
    else
        echo "(no submission id found, so no log to fetch; try: xcrun notarytool history --keychain-profile $NOTARY_PROFILE)" >&2
    fi
    if [ "$rc" -ne 0 ]; then
        die "notarytool submit exited with status $rc (status: ${status:-unknown})"
    fi
    die "notarization status is '${status:-unknown}', not Accepted"
}

# staple_with_retry APP: staple, retrying because Apple's ticket can lag "Accepted" by a minute
# or two ("Record not found", error 65).
staple_with_retry() {
    local app="$1" try=1
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "+ xcrun stapler staple $app   (up to $STAPLE_TRIES tries, ${STAPLE_DELAY}s apart)"
        return 0
    fi
    while true; do
        echo "+ xcrun stapler staple $app   (try $try of $STAPLE_TRIES)"
        if xcrun stapler staple "$app"; then
            return 0
        fi
        if [ "$try" -ge "$STAPLE_TRIES" ]; then
            die "stapling failed $STAPLE_TRIES times. The notarization was accepted, so retry later with: scripts/release.sh --staple-only $VERSION"
        fi
        echo "Stapling failed (Apple's ticket may not be available yet, 'Record not found'). Retrying in ${STAPLE_DELAY}s ($try of $STAPLE_TRIES tries used)..." >&2
        sleep "$STAPLE_DELAY"
        try=$((try + 1))
    done
}

# Tests source this file for the functions above and stop here.
if [ "${RELEASE_SH_LIB_ONLY:-}" = 1 ]; then
    # shellcheck disable=SC2317
    return 0 2> /dev/null || exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --staple-only) STAPLE_ONLY=1 ;;
        -h | --help) usage ;;
        -*) echo "unknown option: $arg" >&2; usage ;;
        *)
            [ -z "$VERSION" ] || usage
            VERSION="$arg"
            ;;
    esac
done
[ -n "$VERSION" ] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.0.0, got '$VERSION'"

cd "$(dirname "$0")/.."

ZIP_PATH="$BUILD_DIR/Asciiquarium-$VERSION.zip"
NOTARY_ZIP="$BUILD_DIR/Asciiquarium-$VERSION-notarize.zip"
APP="$PRODUCTS_DIR/$PRODUCT"

[ "$DRY_RUN" -eq 1 ] && echo "DRY RUN: nothing below is executed."

# ---- Staple-only mode -------------------------------------------------------------------------
if [ "$STAPLE_ONLY" -eq 1 ]; then
    step "Staple-only: staple, check and re-zip the existing build"
    for tool in codesign ditto plutil spctl; do
        command -v "$tool" > /dev/null 2>&1 || die "required tool not found: $tool"
    done
    xcrun --find stapler > /dev/null 2>&1 || die "xcrun stapler not found (install Xcode's command line tools)"
    if [ "$DRY_RUN" -eq 0 ]; then
        [ -d "$APP" ] || die "nothing to staple: $APP does not exist (run a full release first)"
        BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
        [ "$BUNDLE_VERSION" = "$VERSION" ] \
            || die "the saver in $PRODUCTS_DIR is version $BUNDLE_VERSION, not $VERSION"
    fi
    run codesign --verify --strict -vv "$APP"
    staple_with_retry "$APP"
    run xcrun stapler validate "$APP"
    run spctl -a -vv -t open --context context:primary-signature "$APP"
    run rm -f "$ZIP_PATH"
    run ditto -c -k --keepParent "$APP" "$ZIP_PATH"
    echo
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry run complete. A real run writes $ZIP_PATH."
    else
        echo "Done: $ZIP_PATH"
        shasum -a 256 "$ZIP_PATH"
    fi
    exit 0
fi

# ---- Preflight (read-only) --------------------------------------------------------------------
step "Preflight"

for tool in xcodegen xcodebuild codesign ditto security plutil lipo spctl; do
    command -v "$tool" > /dev/null 2>&1 || die "required tool not found: $tool"
done
xcrun --find notarytool > /dev/null 2>&1 || die "xcrun notarytool not found (install Xcode's command line tools)"
xcrun --find stapler > /dev/null 2>&1 || die "xcrun stapler not found (install Xcode's command line tools)"

# find-identity prints lines like:  1) <40-hex SHA-1> "Developer ID Application: Name (TEAMID)"
IDENTITIES="$(security find-identity -v -p codesigning | grep '"Developer ID Application' || true)"
IDENTITY_COUNT=0
[ -z "$IDENTITIES" ] || IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | wc -l | tr -d ' ')"

WANTED_IDENTITY="${SIGN_IDENTITY:-}"
SIGN_IDENTITY=""
if [ "$IDENTITY_COUNT" -eq 0 ]; then
    MESSAGE='no "Developer ID Application" identity in the keychain. Create one in Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application, then check with: security find-identity -v -p codesigning'
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "warning: $MESSAGE"
        echo "warning: a real run would stop here; the plan below uses a placeholder identity."
        SIGN_IDENTITY="<Developer ID Application identity>"
    else
        die "$MESSAGE"
    fi
else
    if [ -n "$WANTED_IDENTITY" ]; then
        # An explicit SHA-1 (from security find-identity) picks one when several are installed.
        MATCH="$(printf '%s\n' "$IDENTITIES" | grep -F "$WANTED_IDENTITY" || true)"
        [ -n "$MATCH" ] || die "SIGN_IDENTITY=$WANTED_IDENTITY is not one of the installed \"Developer ID Application\" identities"
        IDENTITIES="$MATCH"
    elif [ "$IDENTITY_COUNT" -gt 1 ]; then
        die "found $IDENTITY_COUNT \"Developer ID Application\" identities; export SIGN_IDENTITY=<SHA-1 from security find-identity -v -p codesigning> to pick one"
    fi
    SIGN_IDENTITY="$(printf '%s\n' "$IDENTITIES" | head -n 1 | awk '{print $2}')"
    echo "signing identity: $(printf '%s\n' "$IDENTITIES" | head -n 1 | sed -E 's/^[^"]*"([^"]*)".*$/\1/')"
fi

if [ "$DRY_RUN" -eq 0 ]; then
    # Cheap, read-only call that fails fast if the keychain profile is missing or rejected,
    # before a long build. It prints job history only, never credentials.
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 \
        || die "notarytool keychain profile '$NOTARY_PROFILE' is missing or invalid. Store it with: xcrun notarytool store-credentials $NOTARY_PROFILE"
    echo "notary profile: $NOTARY_PROFILE (ok)"
else
    echo "notary profile: $NOTARY_PROFILE (not checked in a dry run)"
fi

# ---- Build ------------------------------------------------------------------------------------
step "1. Generate the Xcode project"
run xcodegen generate

step "2. Build Release (universal, hardened runtime, secure timestamp)"
run rm -rf "$APP" "$ZIP_PATH" "$NOTARY_ZIP"
run xcodebuild -project Asciiquarium.xcodeproj -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--timestamp" ENABLE_HARDENED_RUNTIME=YES \
    build

if [ "$DRY_RUN" -eq 0 ]; then
    [ -d "$APP" ] || die "build did not produce $APP"
    BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
    [ "$BUNDLE_VERSION" = "$VERSION" ] \
        || die "the built saver is version $BUNDLE_VERSION but you asked for $VERSION; update MARKETING_VERSION in project.yml first"
    ARCHS_BUILT="$(lipo -archs "$APP/Contents/MacOS/Asciiquarium")"
    case " $ARCHS_BUILT " in *" arm64 "*) ;; *) die "binary lacks arm64 (has: $ARCHS_BUILT)" ;; esac
    case " $ARCHS_BUILT " in *" x86_64 "*) ;; *) die "binary lacks x86_64 (has: $ARCHS_BUILT)" ;; esac
    [ ! -e "$PRODUCTS_DIR/AsciiquariumPreview.app" ] || echo "note: $PRODUCTS_DIR also holds the dev-only Preview app (stale; it is not shipped)"
fi

# ---- Verify signature -------------------------------------------------------------------------
step "3. Verify the signature"
run codesign --verify --strict -vv "$APP"
if [ "$DRY_RUN" -eq 0 ]; then
    SIGN_INFO="$(codesign -d --verbose=4 "$APP" 2>&1)"
    printf '%s\n' "$SIGN_INFO" | grep -q 'Authority=Developer ID Application' \
        || die "the saver is not signed with a Developer ID Application certificate"
    printf '%s\n' "$SIGN_INFO" | grep -Eq 'flags=0x[0-9a-f]+\(.*runtime.*\)' \
        || die "the hardened runtime flag is missing from the signature"
    printf '%s\n' "$SIGN_INFO" | grep -q '^Timestamp=' \
        || die "the signature has no secure timestamp"
fi

# ---- Notarize ---------------------------------------------------------------------------------
step "4. Zip for notarization"
run ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"

step "5. Submit to Apple and wait (this contacts Apple)"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "+ xcrun notarytool submit $NOTARY_ZIP --keychain-profile $NOTARY_PROFILE --wait --output-format json"
    echo "  (on a non-zero exit or a status other than Accepted: fetch 'xcrun notarytool log <id>' and stop)"
else
    notarize_zip "$NOTARY_ZIP"
fi

# ---- Staple, check, package -------------------------------------------------------------------
step "6. Staple the ticket to the saver and check it"
staple_with_retry "$APP"
run xcrun stapler validate "$APP"
run spctl -a -vv -t open --context context:primary-signature "$APP"

step "7. Zip the stapled saver"
run ditto -c -k --keepParent "$APP" "$ZIP_PATH"
run rm -f "$NOTARY_ZIP"

echo
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run complete. A real run writes $ZIP_PATH."
else
    echo "Done: $ZIP_PATH"
    shasum -a 256 "$ZIP_PATH"
fi
