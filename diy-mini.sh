 #!/bin/bash

# 修改默认IP
# sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate

# 拉取仓库文件夹
merge_package() {
	if [[ $# -lt 3 ]]; then
		echo "Syntax error: [$#] [$*]" >&2
		return 1
	fi
	trap 'rm -rf "$tmpdir"' EXIT
	branch="$1" curl="$2" target_dir="$3" && shift 3
	rootdir="$PWD"
	localdir="$target_dir"
	[ -d "$localdir" ] || mkdir -p "$localdir"
	tmpdir="$(mktemp -d)" || exit 1
        echo "开始下载：$(echo $curl | awk -F '/' '{print $(NF)}')"
	git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$curl" "$tmpdir"
	cd "$tmpdir"
	git sparse-checkout init --cone
	git sparse-checkout set "$@"
	for folder in "$@"; do
		mv -f "$folder" "$rootdir/$localdir"
	done
	cd "$rootdir"
}

# 更改 Argon 主题背景
rm -rf feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/background/*

# 为固件版本加上编译作者
author="kk160524"
sed -i "s/DISTRIB_DESCRIPTION.*/DISTRIB_DESCRIPTION='%D %V %C by ${author}'/g" package/base-files/files/etc/openwrt_release
sed -i "s/OPENWRT_RELEASE.*/OPENWRT_RELEASE=\"%D %V %C by ${author}\"/g" package/base-files/files/usr/lib/os-release
[ -f "$GITHUB_WORKSPACE/configfiles/99-default-settings-chinese" ] && cp -f $GITHUB_WORKSPACE/configfiles/99-default-settings-chinese package/emortal/default-settings/files/99-default-settings-chinese

# 最大连接数修改为65535
sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=65535' package/base-files/files/etc/sysctl.conf

# 集成CPU性能跑分脚本
if [ -d "$GITHUB_WORKSPACE/configfiles/coremark" ]; then
    cp -f $GITHUB_WORKSPACE/configfiles/coremark/coremark-arm64 package/base-files/files/bin/coremark-arm64
    cp -f $GITHUB_WORKSPACE/configfiles/coremark/coremark-arm64.sh package/base-files/files/bin/coremark.sh
    chmod 755 package/base-files/files/bin/coremark-arm64
    chmod 755 package/base-files/files/bin/coremark.sh
fi

# 定时限速插件
git clone --depth=1 https://github.com/sirpdboy/luci-app-eqosplus package/luci-app-eqosplus

# 禁用 rust ci-llvm
sed -i 's/ci-llvm=true/ci-llvm=false/g' feeds/packages/lang/rust/Makefile 2>/dev/null || true

# PCIe 限制从 Gen2(0x02) 修改为 Gen3(0x03)
sed -i 's/max-link-speed = <0x02>;/max-link-speed = <0x03>;/g' $(find target/linux/rockchip/ -name "*.dtsi" -o -name "*.dts" -o -name "*.patch" 2>/dev/null)

# 追加硬件与驱动包到 .config 确保被打包编译
cat <<EOF >> .config
CONFIG_PACKAGE_kmod-r8125=y
CONFIG_PACKAGE_kmod-nvme=y
CONFIG_PACKAGE_kmod-ata-ahci-dwc=y
CONFIG_PACKAGE_kmod-hwmon-pwmfan=y
CONFIG_PACKAGE_kmod-thermal=y
EOF

# 彻底修复 Rust 编译时误删 Cargo.toml.orig 的问题
if [ -f "feeds/packages/lang/rust/Makefile" ]; then
    # 替换 Rust Makefile 中的补丁清理行为
    sed -i '/patch-kernel.sh/s/$/ || true/' feeds/packages/lang/rust/Makefile
    
    # 在 Rust 解压/补丁完成后，自动将所有 Cargo.toml 复制一份为 Cargo.toml.orig
    sed -i '/Build\/Patch/a \ \tfind $(PKG_BUILD_DIR) -name "Cargo.toml" -exec cp {} {}.orig \\;' feeds/packages/lang/rust/Makefile
fi

# 更新并安装 Feeds
./scripts/feeds update -a
./scripts/feeds install -a
