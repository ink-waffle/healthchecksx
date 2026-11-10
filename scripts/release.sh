#!/bin/zsh
# Builds a Release, publishes it on GitHub and points the ink-waffle/tap cask at it.
set -euo pipefail
cd "${0:A:h:h}"

products=$PWD/build/dist
xcodebuild -quiet -project HealthchecksX.xcodeproj -scheme HealthchecksX -configuration Release \
  -destination 'generic/platform=macOS' -allowProvisioningUpdates SYMROOT="$products" OBJROOT="$products/obj"

app=$products/Release/HealthchecksX.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
zip=$PWD/build/HealthchecksX-$version.zip
ditto -c -k --keepParent "$app" "$zip"

gh release create "v$version" "$zip" -R ink-waffle/healthchecksx --title "$version" --notes "HealthchecksX $version"

sha=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)
tap=$(brew --repository ink-waffle/tap)
sed -i '' -E "s/^( +version ).*/\1\"$version\"/; s/^( +sha256 ).*/\1\"$sha\"/" "$tap/Casks/healthchecksx.rb"

print "Published $version. Commit and push the cask in $tap."
