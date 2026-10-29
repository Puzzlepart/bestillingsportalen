#!/usr/bin/env bash
# Builds the files attached to a GitHub release. Run from anywhere in the repo:
#
#   .github/scripts/build-release-assets.sh 1.0.1 [out-dir]
#
# The version must match VERSION and the first three parts of each SPFx solution's
# package-solution.json - a tag that disagrees with them would publish packages stamped
# with another version than the release. Produces, in out-dir (default: release-assets):
#
#   bestillingsportalen-<version>.zip          The repo at this commit with the built .sppkg
#                                              in place, ready for deploy.ps1 -SkipSPFxBuild
#   <package>-<version>.sppkg                  Each SPFx package, for manual app catalog upload
#   bestillingsportalen-teams-app-<version>.zip The Teams app, packaged as deploy.ps1 does it
#   Bestillingsportalen-Flows_unmanaged.zip    The Power Automate solution (Source/Flows)
#   SHA256SUMS.txt
#
# and release-notes.md (the version's CHANGELOG.md section) next to out-dir.
# Set SKIP_SPFX_BUILD=1 to package the .sppkg files that are already built.
set -euo pipefail

version="${1:?Usage: build-release-assets.sh <version> [out-dir]}"
root="$(git rev-parse --show-toplevel)"
out="$(realpath -m "${2:-$root/release-assets}")"
notes="$(dirname "$out")/release-notes.md"

fail() { echo "::error::$*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version '$version' is not MAJOR.MINOR.PATCH"
fileVersion="$(tr -d '[:space:]' < "$root/VERSION")"
[[ "$fileVersion" == "$version" ]] || fail "VERSION is '$fileVersion', not '$version'"

rm -rf "$out"
mkdir -p "$out"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# Each subfolder with config/package-solution.json is a solution, as in deploy.ps1
solutions=()
for config in "$root"/Source/SharePointFramework/*/config/package-solution.json; do
    solutions+=("$(dirname "$(dirname "$config")")")
done
[[ ${#solutions[@]} -gt 0 ]] || fail "No SPFx solutions under Source/SharePointFramework"

for solution in "${solutions[@]}"; do
    name="$(basename "$solution")"
    config="$solution/config/package-solution.json"
    solutionVersion="$(jq -r '.solution.version' "$config" | cut -d. -f1-3)"
    [[ "$solutionVersion" == "$version" ]] || fail "$name: package-solution.json has version $solutionVersion, not $version"

    if [[ "${SKIP_SPFX_BUILD:-}" != "1" ]]; then
        echo "Building $name"
        (cd "$solution" && npm ci --no-audit --no-fund && npm run build)
    fi

    sppkg="$solution/sharepoint/$(jq -r '.paths.zippedPackage' "$config")"
    [[ -f "$sppkg" ]] || fail "$name: $sppkg was not built"
    cp "$sppkg" "$out/$(basename "$sppkg" .sppkg)-$version.sppkg"

    # Teams app: icons + manifest stamped with the version, zipped flat (see PublishTeamsApp)
    if [[ -f "$solution/teams/manifest.json" ]]; then
        teams="$staging/teams-$name"
        mkdir -p "$teams"
        find "$solution/teams" -maxdepth 1 -type f ! -name manifest.json -exec cp {} "$teams/" \;
        jq --arg v "$version" '.version = $v' "$solution/teams/manifest.json" > "$teams/manifest.json"
        (cd "$teams" && zip -q -X "$out/bestillingsportalen-teams-app-$version.zip" ./*)
    fi
done

# Installation package: the committed files plus the built .sppkg where -SkipSPFxBuild looks
package="$staging/bestillingsportalen-$version"
mkdir -p "$package"
git -C "$root" archive --format=tar HEAD | tar -x -C "$package"
for solution in "${solutions[@]}"; do
    config="$solution/config/package-solution.json"
    relative="${solution#"$root"/}"
    target="$package/$relative/sharepoint/$(dirname "$(jq -r '.paths.zippedPackage' "$config")")"
    mkdir -p "$target"
    cp "$solution/sharepoint/$(jq -r '.paths.zippedPackage' "$config")" "$target/"
done
(cd "$staging" && zip -q -r -X "$out/bestillingsportalen-$version.zip" "bestillingsportalen-$version")

cp "$root/Source/Flows/Bestillingsportalen-Flows_unmanaged.zip" "$out/"

(cd "$out" && sha256sum -- * > SHA256SUMS.txt)

# Release notes: the version's section in CHANGELOG.md, without its heading
awk -v v="$version" '
    /^## / { if (inSection) exit; if (index($0, "## " v " ") == 1 || $0 == "## " v) { inSection = 1; next } }
    inSection { print }
' "$root/CHANGELOG.md" > "$notes"
[[ -s "$notes" ]] || fail "CHANGELOG.md has no section for $version"

echo "Release assets in $out:"
ls -l "$out"
