#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
output_app="${1:-${package_dir}/.build/NekoBox.app}"
swift build --package-path "${package_dir}" -c release
binary_dir="$(swift build --package-path "${package_dir}" -c release --show-bin-path)"

mkdir -p "${output_app}/Contents/MacOS" "${output_app}/Contents/Resources"
cp "${binary_dir}/NekoBox" "${output_app}/Contents/MacOS/NekoBox"
cp "${package_dir}/Resources/Info.plist" "${output_app}/Contents/Info.plist"
codesign --force --sign - "${output_app}"

print "Built ${output_app}"
