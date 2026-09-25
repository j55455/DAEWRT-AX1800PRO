#!/bin/bash
. $(dirname "$(realpath "$0")")/function.sh
#移除 luci-app-attendedsysupgrade（自编译固件误触在线升级易变砖）
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ DaeWRT-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#开放网络不设密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD=''/g" $WIFI_SH
	sed -i "s/BASE_ENC='.*'/BASE_ENC='none'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='AU'/g" $WIFI_UC
	#开放网络不设密码
	sed -i "s/encryption='.*'/encryption='none'/g" $WIFI_UC
	sed -i "/key=/d" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

vlmcsd_patches="./feeds/packages/net/vlmcsd/patches/"
[ -f "../patches/001-fix_compile_with_ccache.patch" ] && mkdir -p $vlmcsd_patches && cp -f ../patches/001-fix_compile_with_ccache.patch $vlmcsd_patches

#修复dropbear
# #sed -i "s/Interface/DirectInterface/" ./package/network/services/dropbear/files/dropbear.config
# sed -i "/Interface/d" ./package/network/services/dropbear/files/dropbear.config
# #拷贝files 文件夹到编译目录
# cp -r ../files ./

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置（若存在 Config/PRIVATE.txt）
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from Config/PRIVATE.txt..."
	cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ $WRT_TARGET == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# 针对 AX1800 Pro 1GB 内存注入满血网络栈参数与高并发调优
SYSCTL_CONF="./package/base-files/files/etc/sysctl.conf"
if [ -f "$SYSCTL_CONF" ]; then
	cat >> $SYSCTL_CONF << 'EOF'

# 1GB RAM 网络栈与高并发代理调优 (AX1800 Pro)
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_notsent_lowat = 16384
net.netfilter.nf_conntrack_max = 500000
net.core.bpf_jit_enable = 1
net.core.bpf_jit_harden = 0
vm.min_free_kbytes = 32768
vm.vfs_cache_pressure = 50
EOF
	echo "AX1800 Pro 1GB sysctl tuning injected!"
fi

# 注入启动期硬件与中断优化（rc.local 每次开机均执行）
RC_LOCAL="./package/base-files/files/etc/rc.local"
if [ -f "$RC_LOCAL" ]; then
	sed -i '/^exit 0/d' "$RC_LOCAL"
	cat >> "$RC_LOCAL" << 'EOF'

# 优化连接跟踪哈希桶深度（配合 500000 连接上限建立 131072 桶，降低软中断链表遍历开销）
[ -e /sys/module/nf_conntrack/parameters/hashsize ] && echo 131072 > /sys/module/nf_conntrack/parameters/hashsize

# 为所有网卡队列开启 4 核软中断并发处理 (RPS，分担 host CPU 代理与非卸载流量)
for q in /sys/class/net/*/queues/rx-*; do
	[ -e "$q/rps_cpus" ] && echo "f" > "$q/rps_cpus"
done

# 锁定 CPU 最高工作频率与 Performance 调速器，消除调频延迟毛刺
for gov in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
	[ -e "$gov" ] && echo "performance" > "$gov"
done

# 守卫：防止 Nikki bypass 掉回 0（杜绝页面误保存或订阅更新覆写）
if [ -f /etc/config/nikki ]; then
	[ "$(uci -q get nikki.proxy.bypass_china_mainland_ip)" != "1" ] && {
		uci -q set nikki.proxy.bypass_china_mainland_ip='1'
		uci -q set nikki.proxy.bypass_china_mainland_ip6='1'
		uci -q commit nikki
		/etc/init.d/nikki reload >/dev/null 2>&1
	}
fi

exit 0
EOF
	echo "AX1800 Pro rc.local boot tuning injected!"
fi

# 固化 Nikki 出厂默认绕过大陆 IP，杜绝国内流量掉入 TUN 网卡
for f in $(find ./ -type f -name "nikki.conf" 2>/dev/null); do
	sed -i "s/option 'bypass_china_mainland_ip' '0'/option 'bypass_china_mainland_ip' '1'/g" "$f"
	sed -i "s/option 'bypass_china_mainland_ip6' '0'/option 'bypass_china_mainland_ip6' '1'/g" "$f"
	echo "Patched $f: bypass_china_mainland_ip defaulted to 1"
done

# 注入首次开机出厂预设（流表全硬件加速、4核软中断均衡、WAN MTU 1492、开放WiFi、Nikki出厂直连）
mkdir -p ./package/base-files/files/etc/uci-defaults
cat > ./package/base-files/files/etc/uci-defaults/99-jdc-defaults << 'EOF'
#!/bin/sh
# 1. 激活 4 核心网卡软中断均衡 (RPS)
uci -q set network.globals.packet_steering='1'

# 2. 固化 WAN 口 MTU 为 1492，贴合上级光猫 PPPoE 路径消除分片
uci -q set network.wan.mtu='1492'

# 3. 激活防火墙全硬件流表加速 (Flow Offloading)
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'

# 4. 确保 WAN 口开启 TCP MSS 自动规约 (MSS Clamping)
uci -q set firewall.@zone[1].mtu_fix='1'

# 5. 确保 WiFi 无线为开放网络，无密码
for w in $(uci -q show wireless | grep '=wifi-iface' | cut -d'.' -f2 | cut -d'=' -f1); do
	uci -q set wireless.${w}.ssid='qf'
	uci -q set wireless.${w}.encryption='none'
	uci -q del wireless.${w}.key
done

# 6. 固化 Nikki 大陆 IP 直连 bypass，彻底杜绝回退到单核 TUN
if [ -f /etc/config/nikki ]; then
	uci -q set nikki.proxy.bypass_china_mainland_ip='1'
	uci -q set nikki.proxy.bypass_china_mainland_ip6='1'
	uci -q commit nikki
fi

uci -q commit network
uci -q commit firewall
uci -q commit wireless
exit 0
EOF
chmod +x ./package/base-files/files/etc/uci-defaults/99-jdc-defaults
echo "AX1800 Pro 99-jdc-defaults injected!"

# Samba4 局域网千兆传输性能调优与 root 登录预设
SAMBA_TEMPLATE=$(find ./feeds/packages/net/samba4/ -type f -name "smb.conf.template" 2>/dev/null)
if [ -f "$SAMBA_TEMPLATE" ]; then
	sed -i 's/invalid users = root/# invalid users = root/g' "$SAMBA_TEMPLATE"
	sed -i 's/#use sendfile = yes/use sendfile = yes/g' "$SAMBA_TEMPLATE"
	sed -i 's/#aio read size = 0/aio read size = 1/g' "$SAMBA_TEMPLATE"
	sed -i 's/#aio write size = 0/aio write size = 1/g' "$SAMBA_TEMPLATE"
	echo "Samba4 template tuned for AX1800 Pro!"
fi

# 预置 kenzok8/openwrt-daede 专属更新软件源与公钥（仅 daed 变体，使固件自带 1.28+ 更新通道）
# 使用独立的 dllkids.list 避开 apk-openssl 自带的 customfeeds.list，避免 rootfs 安装时冲突
if [ "${WRT_VARIANT:-daed}" = "daed" ]; then
	mkdir -p ./package/base-files/files/etc/apk/keys ./package/base-files/files/etc/apk/repositories.d
	curl -fsSL https://down.dllkids.xyz/openwrt-feed/keys/dllkids-feed.pub.pem -o ./package/base-files/files/etc/apk/keys/dllkids-feed.pub.pem 2>/dev/null || true
	echo "https://down.dllkids.xyz/openwrt-feed/25.12/aarch64_cortex-a53/packages.adb" > ./package/base-files/files/etc/apk/repositories.d/dllkids.list
else
	echo "Variant ${WRT_VARIANT}: skip daede update feed injection"
fi
