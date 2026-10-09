#!/bin/bash

set -x
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/pins.env"

OP_author="$(printf '%s' "${OP_author:-openwrt-onecloud}" | tr -cd 'A-Za-z0-9._-')"
OP_author="${OP_author:-openwrt-onecloud}"

pin_clone() {
	local dest="$1" url="$2" commit="$3"
	shift 3
	rm -rf "$dest"
	git init "$dest"
	git -C "$dest" remote add origin "$url"
	if [ "$#" -gt 0 ]; then
		git -C "$dest" sparse-checkout init --cone
		git -C "$dest" sparse-checkout set "$@"
	fi
	git -C "$dest" fetch --depth 1 origin "$commit"
	git -C "$dest" checkout --detach FETCH_HEAD
	rm -rf "$dest/.git"
}

pin_clone /tmp/immortalwrt-pin https://github.com/immortalwrt/immortalwrt.git "$IMMORTAL_REV" \
	package/emortal/automount package/emortal/autosamba
mkdir -p package
cp -a /tmp/immortalwrt-pin/package/emortal/automount /tmp/immortalwrt-pin/package/emortal/autosamba package/
rm -rf /tmp/immortalwrt-pin

pin_clone package/autocore-arm https://github.com/sbwml/autocore-arm.git "$AUTOCORE_REV"
pin_clone package/xd https://github.com/shiyu1314/openwrt-feeds.git "$FEEDS_PACKAGES_REV"
pin_clone package/porxy https://github.com/shiyu1314/openwrt-feeds.git "$FEEDS_PROXY_REV"


rm -rf feeds/luci/applications/{luci-app-dockerman,luci-app-samba4,luci-app-aria2}
rm -rf feeds/packages/net/{samba4,v2ray-geodata,mosdns,sing-box,aria2,ariang,adguardhome}
rm -rf feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js


# kenrel Vermagic
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH target/linux/generic/kernel-6.12 | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic


sed -i 's/^PKG_BUILD_PARALLEL:=1$/PKG_BUILD_PARALLEL:=1\nPKG_FORTIFY_SOURCE:=0/' package/libs/xcrypt/libxcrypt/Makefile



# drop attendedsysupgrade
sed -i '/luci-app-attendedsysupgrade/d' \
    feeds/luci/collections/luci-nginx/Makefile \
    feeds/luci/collections/luci-ssl-openssl/Makefile \
    feeds/luci/collections/luci-ssl/Makefile \
    feeds/luci/collections/luci/Makefile
    
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd-mod-ubus //' feeds/luci/collections/luci/Makefile
sed -i 's/+uhttpd /+luci-nginx /g' feeds/luci/collections/luci-light/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl-openssl/Makefile
sed -i "s/+luci /+luci-nginx /g" feeds/luci/collections/luci-ssl/Makefile
sed -i 's/+uhttpd +uhttpd-mod-ubus /+luci-nginx /g' feeds/packages/net/wg-installer/Makefile
sed -i '/uhttpd-mod-ubus/d' feeds/luci/collections/luci-light/Makefile
sed -i 's/+luci-nginx \\$/+luci-nginx/' feeds/luci/collections/luci-light/Makefile


sed -i 's/libustream-mbedtls/libustream-openssl/' include/target.mk



pushd feeds/luci
    patch -p1 < 0001-luci-mod-system-add-modal-overlay-dialog-to-reboot.patch
    patch -p1 < 0002-luci-mod-status-displays-actual-process-memory-usage.patch
    patch -p1 < 0003-luci-mod-status-storage-index-applicable-only-to-val.patch
    patch -p1 < 0004-luci-mod-status-firewall-disable-legacy-firewall-rul.patch
    patch -p1 < 0005-luci-mod-system-add-refresh-interval-setting.patch
    patch -p1 < 0006-luci-mod-system-mounts-add-docker-directory-mount-po.patch
    patch -p1 < 0007-luci-mod-system-add-ucitrack-luci-mod-system-zram.js.patch
    patch -p1 < 0004-luci-add-firewall-add-custom-nft-rule-support.patch
popd



patch -p1 --no-backup-if-mismatch < 100-openwrt-firewall4-add-custom-nft-command-support.patch
patch -p1 --no-backup-if-mismatch < 0012-include-kernel-Always-collect-module-symvers.patch
patch -p1 --no-backup-if-mismatch < 0013-include-netfilter-update-kernel-config-options-for-l.patch
patch -p1 --no-backup-if-mismatch < 001-rust-disable-ci-mode.patch

# fstools
rm -rf package/system/fstools
pin_clone package/system/fstools https://github.com/sbwml/package_system_fstools.git "$FSTOOLS_REV"
# util-linux
rm -rf package/utils/util-linux
pin_clone package/utils/util-linux https://github.com/sbwml/package_utils_util-linux.git "$UTIL_LINUX_REV"

# nghttp3
rm -rf feeds/packages/libs/nghttp3
pin_clone package/libs/nghttp3 https://github.com/sbwml/package_libs_nghttp3.git "$NGHTTP3_REV"

# ngtcp2
rm -rf feeds/packages/libs/ngtcp2
pin_clone package/libs/ngtcp2 https://github.com/sbwml/package_libs_ngtcp2.git "$NGTCP2_REV"

# curl - third-party replacement, pinned. Used by passwall's time_pretransfer check.
rm -rf feeds/packages/net/curl
pin_clone feeds/packages/net/curl https://github.com/sbwml/feeds_packages_net_curl.git "$CURL_REV"

# nginx - third-party replacement, pinned
rm -rf feeds/packages/net/nginx
pin_clone feeds/packages/net/nginx https://github.com/sbwml/feeds_packages_net_nginx.git "$NGINX_REV"
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g;s/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/nginx/files/nginx.init

# nginx - ubus
sed -i 's/ubus_parallel_req 2/ubus_parallel_req 6/g' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 300;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

# uwsgi - fix timeout
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# disable error log
sed -i "s/procd_set_param stderr 1/procd_set_param stderr 0/g" feeds/packages/net/uwsgi/files/uwsgi.init

# uwsgi - performance
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

# rpcd - fix timeout
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

# luci-compat - remove extra line breaks from description
sed -i '/<br \/>/d' feeds/luci/modules/luci-compat/luasrc/view/cbi/full_valuefooter.htm


# golang 26.x replacement, pinned
rm -rf feeds/packages/lang/golang
pin_clone feeds/packages/lang/golang https://github.com/sbwml/packages_lang_golang.git "$GOLANG_REV"

# Feeds were already fetched from the pinned feeds.conf.default.
# Do not update again: a second update resets the local feed patches above.
./scripts/feeds install -a


rm -rf package/base-files/files/etc/banner

sed -i "s/%D %V %C/%D %V $(TZ=UTC-8 date +%Y.%m.%d)/" package/base-files/files/etc/openwrt_release

sed -i "s/%R/by $OP_author/" package/base-files/files/etc/openwrt_release

date=$(date +"%Y-%m-%d")
echo "                                                    " >> package/base-files/files/etc/banner
echo "  _______                     ________        __" >> package/base-files/files/etc/banner
echo " |       |.-----.-----.-----.|  |  |  |.----.|  |_" >> package/base-files/files/etc/banner
echo " |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|" >> package/base-files/files/etc/banner
echo " |_______||   __|_____|__|__||________||__|  |____|" >> package/base-files/files/etc/banner
echo "          |__|" >> package/base-files/files/etc/banner
echo " -----------------------------------------------------" >> package/base-files/files/etc/banner
echo "         %D ${date} by $OP_author                     " >> package/base-files/files/etc/banner
echo " -----------------------------------------------------" >> package/base-files/files/etc/banner
