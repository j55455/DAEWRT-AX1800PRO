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
	#修改WIFI地区（锁定 AU：兼顾覆盖与散热，避免 US 29dBm 极限烤机）
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

# QWRT 精髓调优：关闭 TCP 窗口检测（杜绝 NSS 硬件加速与透明代理流量被误杀断流）
net.netfilter.nf_conntrack_tcp_no_window_check = 1
# 连接建立保活超时从 5 天砍至 2 小时，高并发 P2P 秒级释放陈旧会话，杜绝爆表
net.netfilter.nf_conntrack_tcp_timeout_established = 7440
# 关闭 conntrack 冗余校验和计算，节省转发 CPU 周期
net.netfilter.nf_conntrack_checksum = 0
# 注意：6.12 + fw4(nftables) 未加载 br_netfilter 模块，写入 net.bridge.* 会触发 sysctl unknown key 报错，故移除
# 跨接口 ARP 隔离，防止多网段 ARP 污染
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.default.arp_ignore = 1
# 内核 Panic 3 秒后自动硬重启，杜绝死机失联
kernel.panic = 3
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

# 固化 MosDNS 启动脚本时区为 Asia/Shanghai 并延后启动顺序（START=99 确保晚于 Nikki 启动），杜绝开机境外 DoH 直连被 GFW 重置
for f in $(find ./ -type f -name "mosdns.init" 2>/dev/null); do
	sed -i 's/^START=.*/START=99/g' "$f"
	sed -i '/rm -rf \/tmp\/log\/mosdns\*/a \	> /var/log/mosdns.log' "$f"
	if ! grep -q 'TZ="Asia/Shanghai"' "$f"; then
		sed -i '/procd_open_instance/a \	procd_set_param env TZ="Asia/Shanghai"' "$f"
		echo "Patched $f: TZ=Asia/Shanghai injected into mosdns.init"
	fi
done

# 注入首次开机出厂预设（流表全硬件加速、4核软中断均衡、WAN MTU 1492、开放WiFi、Nikki出厂直连）
mkdir -p ./package/base-files/files/etc/uci-defaults
cat > ./package/base-files/files/etc/uci-defaults/99-jdc-defaults << 'EOF'
#!/bin/sh
# 1. 激活 4 核心网卡软中断均衡 (RPS)
uci -q set network.globals.packet_steering='1'

# 2. 固化 WAN 口 MTU 为 1492，贴合上级光猫 PPPoE 路径消除分片
uci -q set network.wan.mtu='1492'

# 3. 关闭 Linux 通用流表（交由高通 NSS ECM 硬件流表接管，避免两套流表互抢）
uci -q set firewall.@defaults[0].flow_offloading='0'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'

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

# 7. 固化系统与 MosDNS 时区软链接
[ -e /usr/share/zoneinfo/Asia/Shanghai ] && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.@system[0].timezone='CST-8'
uci -q commit system

# 8. 预设 CPU 调频为 Schedutil 动态平衡模式，额定最高 1.2GHz（消除发热与断流，保留 Web 自由调节）
if [ -f /etc/config/cpufreq ]; then
	uci -q set cpufreq.cpufreq.governor0='schedutil'
	uci -q set cpufreq.cpufreq.minfreq0='864000'
	uci -q set cpufreq.cpufreq.maxfreq0='1200000'
	uci -q commit cpufreq
fi

# 9. 固化 NSS 3 队列多核中断绑定，释放 CPU 0 专供系统与代理
if [ -f /etc/config/nss ]; then
	uci -q set nss.general.enable_rps='1'
	uci -q commit nss
fi

# 10. 锁定 WiFi 国家码为 AU（兼顾覆盖与散热，避免 US 极限功率烤机）
for w in $(uci -q show wireless | grep '=wifi-device' | cut -d'.' -f2 | cut -d'=' -f1); do
	uci -q set wireless.${w}.country='AU'
done

# 11. Dnsmasq 缓存交由 MosDNS 接管（cachesize=0），仅设置 EDNS0 大小规约
uci -q set dhcp.@dnsmasq[0].cachesize='0'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q commit dhcp

uci -q commit network
uci -q commit firewall
uci -q commit wireless
exit 0
EOF
chmod +x ./package/base-files/files/etc/uci-defaults/99-jdc-defaults
echo "AX1800 Pro 99-jdc-defaults injected!"

# 预置动态 RPS/XPS 智能多核心避让分流脚本
mkdir -p ./package/base-files/files/etc/hotplug.d/net
cat > ./package/base-files/files/etc/hotplug.d/net/20-smp-tune << 'EOF'
#!/bin/sh
[ "$ACTION" = add ] || exit

NPROCS="$(grep -c "^processor.*:" /proc/cpuinfo)"
[ "$NPROCS" -gt 1 ] || exit

PROC_MASK="$(( (1 << $NPROCS) - 1 ))"

find_irq_cpu() {
	local dev="$1"
	local match="$(grep -m 1 "$dev\$" /proc/interrupts)"
	local cpu=0

	[ -n "$match" ] && {
		set -- $match
		shift
		for cur in $(seq 1 $NPROCS); do
			[ "$1" -gt 0 ] && {
				cpu=$(($cur - 1))
				break
			}
			shift
		done
	}

	echo "$cpu"
}

set_hex_val() {
	local file="$1"
	local val="$2"
	val="$(printf %x "$val")"
	[ -n "$DEBUG" ] && echo "$file = $val"
	echo "$val" > "$file"
}

exec 512>/var/lock/smp_tune.lock
flock 512 || exit 1

for dev in /sys/class/net/*; do
	[ -d "$dev" ] || continue
	[ -n "$(ls "${dev}/" 2>/dev/null | grep '^lower_')" ] && continue
	[ -d "${dev}/device" ] || continue

	device="$(readlink "${dev}/device")"
	device="$(basename "$device")"
	irq_cpu="$(find_irq_cpu "$device")"
	irq_cpu_mask="$((1 << $irq_cpu))"

	for q in ${dev}/queues/rx-*; do
		[ -e "$q/rps_cpus" ] && set_hex_val "$q/rps_cpus" "$(($PROC_MASK & ~$irq_cpu_mask))"
	done

	idx=$(($irq_cpu + 1))
	for q in ${dev}/queues/tx-*; do
		[ -e "$q/xps_cpus" ] && set_hex_val "$q/xps_cpus" "$((1 << $idx))"
		idx=$(($idx + 1))
		[ "$idx" -ge "$NPROCS" ] && idx=0
	done
done
EOF
chmod +x ./package/base-files/files/etc/hotplug.d/net/20-smp-tune

# 预置移动存储设备热插拔自动挂载 Samba4 共享
mkdir -p ./package/base-files/files/etc/hotplug.d/block
cat > ./package/base-files/files/etc/hotplug.d/block/20-smb << 'EOF'
#!/bin/sh
. /lib/functions.sh
. /lib/functions/service.sh

config_file="/etc/config/samba4"
[ -f "$config_file" ] || config_file="/etc/config/samba"
smb_service="samba4"
[ -x "/etc/init.d/samba4" ] || smb_service="samba"

global=0

wait_for_init() {
	for i in $(seq 30); do
		[ -e /tmp/procd.done ] && return
		sleep 1
	done
}

smb_handle() {
	config_get path $1 path
	[ "$path" = "$2" ] && global=1
}

device=$(basename $DEVPATH)

case "$ACTION" in
	add)
		case "$device" in
			sd*|hd*|vd*) ;;
			*) return ;;
		esac

		path="/dev/$device"
		wait_for_init

		cat /proc/mounts | while read j; do
			str=${j%% *}
			if [ "$str" = "$path" ]; then
				strr=${j#* }
				target=${strr%% *}
				global=0
				config_load "$smb_service"
				config_foreach smb_handle sambashare "$target"
				name=${target#*/mnt/}

				if [ $global -eq 0 ]; then
					echo -e "\nconfig sambashare" >> $config_file
					echo -e "\toption auto '1'" >> $config_file
					echo -e "\toption name '$name'" >> $config_file
					echo -e "\toption path '$target'" >> $config_file
					echo -e "\toption read_only 'no'" >> $config_file
					echo -e "\toption guest_ok 'yes'" >> $config_file
					echo -e "\toption create_mask '0666'" >> $config_file
					echo -e "\toption dir_mask '0777'" >> $config_file
					echo -e "\toption device '$device'" >> $config_file
					/etc/init.d/$smb_service reload >/dev/null 2>&1
					return
				fi
			fi
		done
		;;
	remove)
		i=0
		while true; do
			dev=$(uci -q get ${smb_service}.@sambashare[$i].device)
			[ -z "$dev" ] && break
			if [ "$dev" = "$device" ]; then
				uci -q delete ${smb_service}.@sambashare[$i]
				uci -q commit $smb_service
				/etc/init.d/$smb_service reload >/dev/null 2>&1
				return
			fi
			i=$((i + 1))
		done
		;;
esac
EOF
chmod +x ./package/base-files/files/etc/hotplug.d/block/20-smb

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
