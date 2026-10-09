#!/bin/bash
# Clone the pinned OpenWrt revision and write pinned feed URLs.
# Usage: sh/checkout-openwrt.sh <dest-dir>
set -euo pipefail

DEST="${1:?destination directory required}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/pins.env"

rm -rf "$DEST"
git init "$DEST"
git -C "$DEST" remote add origin "$OPENWRT_URL"
git -C "$DEST" fetch --depth 1 origin "$OPENWRT_REV"
git -C "$DEST" checkout --detach FETCH_HEAD

cat > "$DEST/feeds.conf.default" <<EOF
src-git packages https://github.com/openwrt/packages.git^${FEED_PACKAGES}
src-git luci https://github.com/openwrt/luci.git^${FEED_LUCI}
src-git routing https://github.com/openwrt/routing.git^${FEED_ROUTING}
src-git telephony https://github.com/openwrt/telephony.git^${FEED_TELEPHONY}
src-git video https://github.com/openwrt/video.git^${FEED_VIDEO}
EOF

if [ "${PIN_KERNEL_CFG:-0}" = "1" ]; then
	curl -fsSL \
		"https://raw.githubusercontent.com/immortalwrt/immortalwrt/${IMMORTAL_REV}/config/Config-kernel.in" \
		-o "$DEST/config/Config-kernel.in"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
	echo "release_tag=${OPENWRT_LABEL}" >> "$GITHUB_ENV"
	echo "OPENWRT_REV=${OPENWRT_REV}" >> "$GITHUB_ENV"
fi

echo "Checked out OpenWrt ${OPENWRT_REV} (${OPENWRT_LABEL})"
