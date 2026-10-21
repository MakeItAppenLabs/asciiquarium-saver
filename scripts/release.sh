#!/bin/bash
#
# Build, sign, notarize and package Asciiquarium.saver.
#
#   scripts/release.sh [--dry-run] <version>
#
# Produces build/Asciiquarium-<version>.zip containing the signed, notarized, stapled
# Asciiquarium.saver. Maintainer-only: it needs a "Developer ID Application" identity in the
# keychain and a notarytool keychain profile named "asciiquarium-notary" (see README.md).
#
# --dry-run prints every command it would run and runs none of the build, signing or Apple steps.
# The read-only preflight checks still run; a missing identity is reported but does not stop a
# dry run, so the printed plan can be reviewed on any machine.
#
# Credentials never appear here: notarytool reads them from the keychain profile.
# Deliberately no "set -x", which would echo expanded commands.

set -euo pipefail

NOTARY_PROFILE="asciiquarium-notary"
SCHEME="Asciiquarium"
PRODUCT="Asciiquarium.saver"
BUILD_DIR="build"
PRODUCTS_DIR="$BUILD_DIR/Build/Products/Release"

DRY_RUN=0
VERSION=""

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    echo "usage: scripts/release.sh [--dry-run] <version>   (for example 1.0.0)" >&2
    exit 2
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
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

cd "$(dirname "$0")/.."

ZIP_PATH="$BUILD_DIR/Asciiquarium-$VERSION.zip"
NOTARY_ZIP="$BUILD_DIR/Asciiquarium-$VERSION-notarize.zip"
APP="$PRODUCTS_DIR/$PRODUCT"

[ "$DRY_RUN" -eq 1 ] && echo "DRY RUN: nothing below is executed."

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
else
    RESULT_FILE="$(mktemp -t asciiquarium-notary)"
    trap 'rm -f "$RESULT_FILE"' EXIT
    echo "+ xcrun notarytool submit $NOTARY_ZIP --keychain-profile $NOTARY_PROFILE --wait --output-format json"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
        --output-format json > "$RESULT_FILE" || {
        cat "$RESULT_FILE" >&2
        die "notarytool submit failed"
    }
    STATUS="$(plutil -extract status raw -o - "$RESULT_FILE")"
    SUBMISSION_ID="$(plutil -extract id raw -o - "$RESULT_FILE")"
    echo "submission $SUBMISSION_ID: status $STATUS"
    if [ "$STATUS" != "Accepted" ]; then
        echo "--- notarization log ---" >&2
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        die "notarization status is '$STATUS', not Accepted"
    fi
fi

# ---- Staple, check, package -------------------------------------------------------------------
step "6. Staple the ticket to the saver and check it"
run xcrun stapler staple "$APP"
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
