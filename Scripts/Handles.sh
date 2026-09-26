#!/bin/bash

PKG_PATH="$GITHUB_WORKSPACE/$WRT_DIR/package/"

#预置HomeProxy数据
# if [ -d *"homeproxy"* ]; then
# 	echo " "

# 	HP_RULE="surge"
# 	HP_PATH="homeproxy/root/etc/homeproxy"

# 	rm -rf ./$HP_PATH/resources/*

# 	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/
# 	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

# 	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
# 	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
# 	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
# 	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

# 	cd .. && rm -rf ./$HP_RULE/

# 	cd $PKG_PATH && echo "homeproxy date has been updated!"
# fi

#修改qca-nss-drv启动顺序
NSS_DRV="../feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
	echo " "

	sed -i 's/START=.*/START=85/g' $NSS_DRV

	cd $PKG_PATH && echo "qca-nss-drv has been fixed!"
fi

#修改qca-nss-pbuf启动顺序
NSS_PBUF="./kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
	echo " "

	sed -i 's/START=.*/START=86/g' $NSS_PBUF

	cd $PKG_PATH && echo "qca-nss-pbuf has been fixed!"
fi

#修复TailScale配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile")
if [ -f "$TS_FILE" ]; then
	echo " "

	sed -i '/\/files/d' $TS_FILE

	cd $PKG_PATH && echo "tailscale has been fixed!"
fi

#修复Rust编译失败（关闭 ci-llvm，规避 GitHub runner 上 LLVM 断言崩溃）
RUST_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile" -print -quit 2>/dev/null)
if [ -n "$RUST_FILE" ] && [ -f "$RUST_FILE" ]; then
	echo " "

	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"

	cd $PKG_PATH && echo "rust has been fixed!"
fi

#修改argon主题字体和配色
ARGON_CONF=$(find ./ ../feeds/luci/ -maxdepth 5 -type f -wholename "*/luci-app-argon-config/root/etc/config/argon" 2>/dev/null | head -n 1)
if [ -n "$ARGON_CONF" ] && [ -f "$ARGON_CONF" ]; then
	echo " "
	if sed -i "s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" "$ARGON_CONF"; then
		cd $PKG_PATH && echo "theme-argon has been fixed!"
	fi
fi

#修改aurora菜单式样与圆角
AURORA_DIR=$(find ./ ../feeds/luci/ -maxdepth 5 -type d -wholename "*/luci-app-aurora-config/root/usr/share/aurora" 2>/dev/null | head -n 1)
if [ -n "$AURORA_DIR" ] && [ -d "$AURORA_DIR" ]; then
	echo " "
	if find "$AURORA_DIR" -type f -name '*.template' -exec \
		sed -i "s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +; then
		cd $PKG_PATH && echo "theme-aurora templates tuned!"
	fi
fi

#修复aurora主题设计studio.js样式表解析器超时与背景输入无效Bug（消除iframe死锁并放行合规Hex颜色）
for f in $(find ./ ../feeds/ -type f -name "studio.js" 2>/dev/null | grep -E "aurora/studio\.js"); do
	python3 -c "
import sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

old1 = 'n&&o?o.sheet?i():(o.addEventListener(\"load\",i,{once:!0}),o.addEventListener(\"error\",()=>{window.clearTimeout(a),t(new Error(_(\"Unable to load the Aurora stylesheet.\")))},{once:!0})):(window.clearTimeout(a),t(new Error(_(\"Unable to create the theme color resolver.\"))))'
new1 = '(()=>{const _c=()=>(!n||!o||o.sheet)?(i(),!0):!1;if(!_c()){let _k=0;const _tm=setInterval(()=>{_k++;(_c()||_k>20)&&(clearInterval(_tm),i())},25);o.addEventListener(\"load\",()=>{clearInterval(_tm),i()},{once:!0}),o.addEventListener(\"error\",()=>{clearInterval(_tm),i()},{once:!0})}})()'

old2 = 'validate:(e,t,r)=>{if(!r?.trim())return!0;'
new2 = 'validate:(e,t,r)=>{if(!r?.trim()||/^#[0-9a-fA-F]{3,8}$/.test(r.trim()))return!0;'

if old1 in c and old2 in c:
    c = c.replace(old1, new1).replace(old2, new2)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(c)
    print('theme-aurora studio.js successfully patched: ' + p)
else:
    print('theme-aurora studio.js signature mismatch in ' + p)
" "$f"
done

# 优化 cpufreq 启动时序（延后至 85，确保 qualcommax 驱动就绪）与 LuCI 前端易用性
CPUFREQ_INIT=$(find ./ ../feeds/ -type f -name "cpufreq.init" 2>/dev/null | head -n 1)
if [ -n "$CPUFREQ_INIT" ] && [ -f "$CPUFREQ_INIT" ]; then
	sed -i 's/START=15/START=85/g' "$CPUFREQ_INIT"
	echo "cpufreq.init START adjusted to 85!"
fi

CPUFREQ_VIEW=$(find ./ ../feeds/ -type f -name "cpufreq.js" 2>/dev/null | head -n 1)
if [ -n "$CPUFREQ_VIEW" ] && [ -f "$CPUFREQ_VIEW" ]; then
	python3 -c "
import sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

old_val = 'for (let freq of data[1][i].freqs)\n\t\t\t\t\to.value(freq);'
new_val = 'for (let freq of data[1][i].freqs) { let f = parseInt(freq), fl = f >= 1000000 ? (f/1000000).toFixed(2) + \" GHz\" : Math.round(f/1000) + \" MHz\"; if (f === 864000) fl += \" (低负载节能)\"; else if (f === 1200000) fl += \" (官方额定/推荐)\"; else if (f === 1512000) fl += \" (极限睿频/发热高)\"; o.value(freq, fl); }'

old_gov = 'for (let gov of data[1][i].governors)\n\t\t\t\t\to.value(gov);'
new_gov = 'for (let gov of data[1][i].governors) { let gl = (gov === \"schedutil\") ? \"schedutil (动态平衡/低温推荐)\" : (gov === \"performance\") ? \"performance (全核锁最高频/发热大)\" : gov; o.value(gov, gl); }'

if old_gov in c:
    c = c.replace(old_gov, new_gov)
if old_val in c:
    c = c.replace(old_val, new_val)

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('cpufreq.js view labels enhanced!')
" "$CPUFREQ_VIEW"
fi
