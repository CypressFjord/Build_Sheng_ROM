#!/bin/bash

###构建前准备
URL="$1"              #系统包下载地址
GITHUB_ENV="$2"       #输出环境变量
GITHUB_WORKSPACE="$3" #工作目录

Red='\033[1;31m'      #粗体红色
Yellow='\033[1;33m'   #粗体黄色
Blue='\033[1;34m'     #粗体蓝色
Green='\033[1;32m'    #粗体绿色
NC='\033[0m'          #重置颜色

device=sheng          # 设备代号

#系统包系统OS版本号
vendor_os_version=$(echo "$URL" | awk -F'/' '{print $(NF-1)}')
#系统包系统zip名称
vendor_zip_name=$(echo "$URL" | awk -F'/' '{print $NF}' | awk -F'?' '{print $1}')
#Android版本号
android_version=$(echo "$URL" | grep -oE '-user-[0-9]+' | grep -oE '[0-9]+')
#构建时间
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)
#工具位置
a7z="$GITHUB_WORKSPACE"/tools/7zzs
e2fsdroid="$GITHUB_WORKSPACE"/tools/e2fsdroid
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
mke2fs="$GITHUB_WORKSPACE"/tools/mke2fs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
ksud="$GITHUB_WORKSPACE"/tools/ksu_lkm_patch/ksud
ksuinit="$GITHUB_WORKSPACE/tools/ksu_lkm_patch/ksuinit"
ksu_ko="$GITHUB_WORKSPACE/tools/ksu_lkm_patch/android13-5.15_kernelsu.ko"
#创建文件夹
mkdir -p "$GITHUB_WORKSPACE"/tools
mkdir -p "$GITHUB_WORKSPACE"/firmware
mkdir -p "$GITHUB_WORKSPACE"/files
#为文件夹赋予755权限
chmod -R 755 "$GITHUB_WORKSPACE"/tools
chmod -R 755 "$GITHUB_WORKSPACE"/firmware
chmod -R 755 "$GITHUB_WORKSPACE"/files
#声明时间栈数组,支持多层嵌套计时
TIMER_STACK_S=()
TIMER_STACK_NS=()
#开始时间设置)
Start_Time() {
  TIMER_STACK_S+=("$(date +%s)")
  TIMER_STACK_NS+=("$(date +%N)")
}
#结束时间设置
End_Time() {
  local stack_len=${#TIMER_STACK_S[@]}
  if (( stack_len == 0 )); then
    echo -e "${Red}- 警告: 找不到匹配的 Start_Time${NC}"
    return
  fi
#获取栈顶时间
  local last_idx=$((stack_len - 1))
  local Start_s=${TIMER_STACK_S[$last_idx]}
  local Start_ns=${TIMER_STACK_NS[$last_idx]}
#移除栈顶元素，并且重置数组索引
  unset 'TIMER_STACK_S[$last_idx]'
  unset 'TIMER_STACK_NS[$last_idx]'
  TIMER_STACK_S=("${TIMER_STACK_S[@]}")
  TIMER_STACK_NS=("${TIMER_STACK_NS[@]}")
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi 
  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))
  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒${NC}"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒${NC}"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒${NC}"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒${NC}"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒${NC}"
  fi
}
###构建前准备结束

######构建$device官改ROM
echo -e "${Red}- 开始构建$device官改ROM${NC}"
Start_Time

###系统包下载
echo -e "${Red}- 开始系统包下载${NC}"
Start_Time
if [ -f "$GITHUB_WORKSPACE/${vendor_zip_name}" ]; then
  echo -e "${Green}- 检测到本地已存在系统包: ${vendor_zip_name}，跳过网络下载步骤${NC}"
else
  echo -e "${Yellow}- 本地不存在系统包，开始网络下载系统包${NC}"
  aria2c -x16 -s16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "${URL}" &
  wait
fi
End_Time 系统包下载
###系统包下载结束

###解压并分解系统包的文件
echo -e "${Red}- 开始解压并分解系统包的文件${NC}"
Start_Time
mkdir -p "$GITHUB_WORKSPACE"/vendor_zip
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/super
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
mkdir -p "$GITHUB_WORKSPACE"/zip
#解压系统包ZIP
echo -e "${Red}- 开始解压系统包ZIP${NC}"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${vendor_zip_name} -o"$GITHUB_WORKSPACE"/vendor_zip payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${vendor_zip_name}
End_Time 解压系统包ZIP
#分解系统包Payload
echo -e "${Red}- 开始分解系统包Payload${NC}"
Start_Time
$payload_extract -s -o "$GITHUB_WORKSPACE"/firmware/images -i "$GITHUB_WORKSPACE"/vendor_zip/payload.bin -X abl,aop,aop_config,bluetooth,boot,cpucp,devcfg,dsp,dtbo,featenabler,hyp,imagefv,init_boot,keymaster,modem,multiimgqti,qupfw,shrm,tz,uefi,uefisecapp,vbmeta,vbmeta_system,vendor_boot,xbl,xbl_config,xbl_ramdump -T0
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir -i "$GITHUB_WORKSPACE"/vendor_zip/payload.bin -X mi_ext,odm,product,system,system_dlkm,system_ext,vendor,vendor_dlkm -T0
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_zip/payload.bin
End_Time 分解系统包Payload
#分解系统包的Images
echo -e "${Red}- 开始分解系统包的Images${NC}"
Start_Time
for i in mi_ext odm product system system_dlkm system_ext vendor vendor_dlkm; do
echo -e "${Red}- 正在分解$i.img${NC}"
Start_Time
  cd "$GITHUB_WORKSPACE"/images
  sudo $erofs_extract -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x -s
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
End_Time 分解$i.img
done
End_Time 分解系统包的Images
End_Time 解压并分解系统包的文件
###解压并分解系统包的文件结束

###写入系统包的变量
echo -e "${Red}- 开始写入系统包的变量${NC}"
Start_Time
#ROM构建日期
echo -e "${Red}- ROM构建日期: $build_time${NC}"
echo "build_time=$build_time" >>$GITHUB_ENV
#系统包SOTA版本
mi_ext_build_prop=$GITHUB_WORKSPACE/images/mi_ext/etc/build.prop
incremental_version=$(grep "ro.mi.xms.version.incremental=" "$mi_ext_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包SOTA版本: $incremental_version${NC}"
echo "incremental_version=$incremental_version" >>$GITHUB_ENV
#系统包系统版本
echo -e "${Red}- 系统包系统版本: $vendor_os_version${NC}"
echo "vendor_os_version=$vendor_os_version" >>$GITHUB_ENV
#系统包System安全补丁日期
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
port_security_patch=$(grep "ro.build.version.security_patch=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包System安全补丁日期: $port_security_patch${NC}"
echo "port_security_patch=$port_security_patch" >>$GITHUB_ENV
#系统包Vendor安全补丁日期
vendor_build_prop=$GITHUB_WORKSPACE/images/vendor/build.prop
vendor_security_patch=$(grep "ro.vendor.build.security_patch=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包Vendor安全补丁日期: $vendor_security_patch${NC}"
echo "vendor_security_patch=$vendor_security_patch" >>$GITHUB_ENV
#系统包System基线版本
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
system_base_line=$(grep "ro.system.build.id=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包System基线版本: $system_base_line${NC}"
echo "system_base_line=$system_base_line" >>$GITHUB_ENV
#系统包Vendor基线版本
vendor_build_prop=$GITHUB_WORKSPACE/images/vendor/build.prop
vendor_base_line=$(grep "ro.vendor.build.id=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包Vendor基线版本: $vendor_base_line${NC}"
echo "vendor_base_line=$vendor_base_line" >>$GITHUB_ENV
End_Time 写入系统包的变量
###写入系统包的变量结束

###功能修复
echo -e "${Red}- 开始功能修复${NC}"
Start_Time
#复制通用文件
echo -e "${Red}- 开始复制通用文件${NC}"
Start_Time
mkdir -p "$GITHUB_WORKSPACE"/images
\cp -rf "$GITHUB_WORKSPACE"/files/common/* "$GITHUB_WORKSPACE"/images/
cat "$GITHUB_WORKSPACE"/files/mi_ext_build.prop >> "$GITHUB_WORKSPACE"/images/mi_ext/etc/build.prop
cat "$GITHUB_WORKSPACE"/files/system_ext_build.prop >> "$GITHUB_WORKSPACE"/images/system_ext/etc/build.prop
End_Time 复制通用文件
#修改build.prop代码
echo -e "${Red}- 开始修改build.prop代码${NC}"
Start_Time
comment_prop() {
    local file="$1" key="$2" k="${2//./\\.}"
    [ -f "$file" ] || { echo -e "${Yellow}- 警告: 文件不存在: $file${NC}"; return; }
    if grep -qE "^${k}=" "$file"; then
        sed -i "s/^${k}=/#${k}=/" "$file"
        echo -e "${Green}- 已注释: ${key} ($file)${NC}"
    elif grep -qE "^#${k}=" "$file"; then
        echo -e "${Yellow}- 跳过: ${key} 已被注释 ($file)${NC}"
    else
        echo -e "${Yellow}- 警告: 未找到 ${key} ($file)${NC}"
    fi
}
set_prop_value() {
    local file="$1" key="$2" old="$3" new="$4" k="${2//./\\.}"
    [ -f "$file" ] || { echo -e "${Yellow}- 警告: 文件不存在: $file${NC}"; return; }
    if grep -qxF "${key}=${new}" "$file"; then
        echo -e "${Yellow}- 跳过: ${key} 已是目标值 ($file)${NC}"
    elif grep -qxF "${key}=${old}" "$file"; then
        sed -i "s|^${k}=${old//\//\\/}\$|${key}=${new}|" "$file"
        echo -e "${Green}- 已修改: ${key}=${old} -> ${new} ($file)${NC}"
    else
        echo -e "${Yellow}- 警告: 未找到 ${key}=${old} ($file)${NC}"
    fi
}
MI_EXT="$GITHUB_WORKSPACE/images/mi_ext/etc/build.prop"
ODM="$GITHUB_WORKSPACE/images/odm/etc/build.prop"
PRODUCT="$GITHUB_WORKSPACE/images/product/etc/build.prop"
comment_prop "$MI_EXT" "ro.miui.support.system.app.uninstall.v2"
set_prop_value "$ODM" "ro.vendor.display.type" "lcd" ""
set_prop_value "$ODM" "ro.vendor.display.idle_default_fps" "50" "60"
comment_prop "$PRODUCT" "ro.miui.cust_erofs"
comment_prop "$PRODUCT" "ro.miui.preinstall_to_data"
comment_prop "$PRODUCT" "ro.miui.cust_img_path"
End_Time 修改build.prop代码
#解锁谷歌国区限制和谷歌快速分享
echo -e "${Red}- 开始解锁谷歌国区限制和谷歌快速分享${NC}"
Start_Time
cn_google_xml="$GITHUB_WORKSPACE"/images/product/etc/permissions/cn.google.services.xml
if [ -f "$cn_google_xml" ]; then
    sed -i '/<feature name="cn.google.services" \/>/d; /<feature name="com.google.android.feature.services_updater" \/>/d' "$cn_google_xml"
    echo -e "${Green}- 已解锁谷歌国区限制和谷歌快速分享${NC}"
else
    echo -e "${Yellow}- 警告: 未找到cn.google.services.xml，跳过此步骤${NC}"
fi
End_Time 解锁谷歌国区限制和谷歌快速分享
##修改sheng.xml
echo -e "${Red}- 开始修改sheng.xml${NC}"
Start_Time
#补全刷新率档位和添加全局高刷
echo -e "${Red}- 开始补全刷新率档位和添加全局高刷${NC}"
Start_Time
sheng_xml="$GITHUB_WORKSPACE"/images/product/etc/device_features/sheng.xml
if [ -f "$sheng_xml" ] && grep -qF '<item>144</item>' "$sheng_xml"; then
    echo -e "${Yellow}- 跳过: 已是目标值${NC}"
elif [ -f "$sheng_xml" ]; then
    sed -i '
    /<integer name="support_max_fps">144<\/integer>/d
    s/<integer name="smart_fps_value">120<\/integer>/<integer name="smart_fps_value">144<\/integer>/
    /<integer-array name="fpsList">/,/<\/integer-array>/{
        /<item>120<\/item>/i\        <item>144</item>
        /<item>60<\/item>/a\        <item>50</item>\
        <item>48</item>\
        <item>30</item>\
        <item>6</item>
    }' "$sheng_xml"
    echo -e "${Green}- 已补全刷新率档位和添加全局高刷${NC}"
else
    echo -e "${Yellow}- 警告: 未找到sheng.xml，跳过此步骤${NC}"
fi
End_Time 补全刷新率档位和添加全局高刷
#添加Xiaomi Pad 6S Pro 12.4 Patch
echo -e "${Red}- 开始添加Xiaomi Pad 6S Pro 12.4 Patch${NC}"
Start_Time
sheng_xml="$GITHUB_WORKSPACE"/images/product/etc/device_features/sheng.xml
if [ -f "$sheng_xml" ]; then
    if grep -qF 'Xiaomi Pad 6S Pro 12.4 Patch' "$sheng_xml"; then
        echo -e "${Yellow}- 跳过: Xiaomi Pad 6S Pro 12.4 Patch已存在${NC}"
    else
        sed -i "/<\/features>/{
            i\\    <!-- Xiaomi Pad 6S Pro 12.4 Patch -->\\
    <!-- default rhythmic eyecare mode -->\\
    <integer name=\"default_eyecare_mode\">2</integer>\\
    <!-- Whether UI show Xiaomi Qingshan Eyecare -->\\
    <bool name=\"support_qingshan_eyecare\">true</bool>\\
    <!-- Whether rhythmic mode 2.0 supported by phone -->\\
    <bool name=\"is_rhythmic_mode_v2_supported\">true</bool>\\
    <!-- Don't let the volume go down when playing videos -->\\
    <bool name=\"support_video_idle_dim\">true</bool>\\
    <!-- Xiaomi Pad 6S Pro 12.4 Patch END -->
            a\\<!-- END Patch -->
        }" "$sheng_xml"
        echo -e "${Green}- 已添加Xiaomi Pad 6S Pro 12.4 Patch${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到sheng.xml，跳过此步骤${NC}"
fi
End_Time 添加XiaomiPad6SPro12.4Patch
End_Time 修改sheng.xml
##修改privapp-permissions-product.xml
echo -e "${Red}- 开始修改privapp-permissions-product.xml${NC}"
Start_Time
#检测并添加WRITE_MEDIA_STORAGE权限
echo -e "${Red}- 开始检测并添加WRITE_MEDIA_STORAGE权限${NC}"
Start_Time
privapp_xml="$GITHUB_WORKSPACE"/images/product/etc/permissions/privapp-permissions-product.xml
if [ -f "$privapp_xml" ]; then
    if awk '
        /<privapp-permissions package="com.miui.securitycenter">/ { inblock=1 }
        inblock && /<permission name="android.permission.WRITE_MEDIA_STORAGE" \/>/ { found=1; exit }
        inblock && /<\/privapp-permissions>/ { exit }
        END { exit !found }
    ' "$privapp_xml"; then
        echo -e "${Yellow}- 跳过: WRITE_MEDIA_STORAGE权限存在${NC}"
    else
        awk '
        /<privapp-permissions package="com.miui.securitycenter">/ { inblock=1; found=0 }
        inblock && /<permission name="android.permission.WRITE_MEDIA_STORAGE" \/>/ { found=1 }
        inblock && /<\/privapp-permissions>/ {
            if (!found) {
                print "      <permission name=\"android.permission.WRITE_MEDIA_STORAGE\" />"
            }
            inblock=0
        }
        { print }
        ' "$privapp_xml" > "${privapp_xml}.tmp" && mv "${privapp_xml}.tmp" "$privapp_xml"
        echo -e "${Green}- 已添加WRITE_MEDIA_STORAGE权限${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到privapp-permissions-product.xml，跳过此步骤${NC}"
fi
End_Time 检测并添加WRITE_MEDIA_STORAGE权限
#添加传送门MIUIContentExtension权限
echo -e "${Red}- 开始添加传送门MIUIContentExtension权限${NC}"
Start_Time
privapp_xml="$GITHUB_WORKSPACE"/images/product/etc/permissions/privapp-permissions-product.xml
if [ -f "$privapp_xml" ]; then
    if grep -qF '<privapp-permissions package="com.miui.contentextension">' "$privapp_xml"; then
        echo -e "${Yellow}- 跳过: com.miui.contentextension权限块已存在${NC}"
    else
        awk '
        /<\/permissions>/ && !inserted {
            print "   <privapp-permissions package=\"com.miui.contentextension\">"
            print "      <permission name=\"android.permission.WRITE_SECURE_SETTINGS\" />"
            print "      <permission name=\"android.permission.READ_CLIPBOARD_IN_BACKGROUND\" />"
            print "      <permission name=\"android.permission.START_FOREGROUND_SERVICES_FROM_BACKGROUND\" />"
            print "   </privapp-permissions>"
            inserted=1
        }
        { print }
        ' "$privapp_xml" > "${privapp_xml}.tmp" && mv "${privapp_xml}.tmp" "$privapp_xml"
        echo -e "${Green}- 已添加传送门MIUIContentExtension权限${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到privapp-permissions-product.xml，跳过此步骤${NC}"
fi
End_Time 添加传送门MIUIContentExtension权限
End_Time 修改privapp-permissions-product.xml
##内置水龙优化
echo -e "${Red}- 开始内置水龙优化${NC}"
Start_Time
#处理cpq调速器
echo -e "${Red}- 开始处理cpq调速器${NC}"
Start_Time
RC_FILE="$GITHUB_WORKSPACE/images/vendor/etc/init/hw/init.qti.kernel.rc"
ANCHOR='write /sys/block/sda/queue/scheduler cpq'
grep -qF "$ANCHOR" "$RC_FILE" || echo -e "${Yellow}- 警告: 未找到cpq锚点${NC}"
sed -i "/${ANCHOR//\//\\/}/a\\
    write /sys/block/sda/queue/iosched/read_expire 4\\
    write /sys/block/sda/queue/iosched/prio_aging_expire 200\\
    write /sys/block/sda/queue/iosched/write_expire 8\\
    write /sys/block/sda/queue/iosched/io_threshold 256\\
    write /sys/block/sda/queue/iosched/async_depth 62" "$RC_FILE"
echo -e "${Green}- 成功处理cpq调速器${NC}"
End_Time 处理cpq调速器
#插入mi_sw_sync权限设置（仅第一个）
echo -e "${Red}- 开始插入mi_sw_sync权限设置（仅第一个）${NC}"
Start_Time
TARGET_RC="$GITHUB_WORKSPACE/images/vendor/etc/init/hw/init.target.rc"
ANCHOR='on post-fs-data'
grep -qF "$ANCHOR" "$TARGET_RC" || echo -e "${Yellow}- 警告: 未找到post-fs-data锚点${NC}"
sed -i "1,/${ANCHOR}/!b; /${ANCHOR}/a\\
    chmod 0666 /dev/mi_sw_sync\\
    restorecon /dev/mi_sw_sync" "$TARGET_RC"
echo -e "${Green}- 成功插入mi_sw_sync权限设置（仅第一个）${NC}"
End_Time 插入mi_sw_sync权限设置（仅第一个）
#关闭F2FS iostat减少读写时锁争用
echo -e "${Red}- 开始关闭F2FS iostat减少读写时锁争用${NC}"
Start_Time
INIT_RC="$GITHUB_WORKSPACE/images/system/system/etc/init/hw/init.rc"
grep -qF "iostat" "$INIT_RC" || echo -e "${Yellow}- 警告: 未找到iostat相关行${NC}"
sed -i '/write \/dev\/sys\/fs\/by-name\/userdata\/iostat_period_ms 1000/d' "$INIT_RC"
sed -i '/write \/dev\/sys\/fs\/by-name\/userdata\/iostat_enable 1/d' "$INIT_RC"
echo -e "${Green}- 成功关闭F2FS iostat减少读写时锁争用${NC}"
End_Time 关闭F2FSiostat减少读写时锁争用
#Amktiao的ZRAM压缩算法优化
Start_Time
echo -e "${Red}- 开始Amktiao的ZRAM压缩算法优化${NC}"
zram_rc="$GITHUB_WORKSPACE"/images/system/system/etc/init/hw/init.rc
perfinit="$GITHUB_WORKSPACE"/images/system_ext/etc/perfinit.conf
if [ -f "$zram_rc" ] && ! grep -qF 'Amktiao ZRAM opt Add' "$zram_rc"; then
    sed -i '/# System server manages zram writeback/a\
    # Amktiao ZRAM opt Add\
    write /proc/sys/vm/page-cluster 0\
    # Amktiao ZRAM opt End' "$zram_rc" && echo -e "${Green}- init.rc已成功修改${NC}"
fi
if [ -f "$perfinit" ] && ! grep -q '"comp_algo"' "$perfinit"; then
    sed -i '/"swap_on": 1,/{p; s/.*/        "comp_algo": "lz4",/}' "$perfinit"
    python3 -c "import json; json.load(open('$perfinit'))" 2>/dev/null \
        && echo -e "${Green}- perfinit.conf已成功修改${NC}" \
        || echo -e "${Yellow}- 严重警告: JSON校验失败${NC}"
fi
End_Time Amktiao的ZRAM压缩算法优化
#vendor_dlkm分区添加内核模块
echo -e "${Red}- 开始vendor_dlkm分区添加内核模块${NC}"
Start_Time
modules_load="$GITHUB_WORKSPACE"/images/vendor_dlkm/lib/modules/modules.load
modules_dep="$GITHUB_WORKSPACE"/images/vendor_dlkm/lib/modules/modules.dep
add_module_load() {
    local ko="$1"
    grep -qxF "$ko" "$modules_load" 2>/dev/null || printf '%s\n' "$ko" >> "$modules_load"
}
add_module_dep() {
    local dep="$1"
    grep -qxF "$dep" "$modules_dep" 2>/dev/null || printf '%s\n' "$dep" >> "$modules_dep"
}
add_module_load "android13-5.15_mi_sw_sync.ko"
add_module_load "android13-5.15_moon_cache.ko"
add_module_load "android13-5.15_moon_kshrink_lruvecd.ko"
add_module_load "android13-5.15_moon_kshrink_slabd.ko"
add_module_load "android13-5.15_moon_look_around.ko"
add_module_load "android13-5.15_moon_mapped_protect.ko"
add_module_dep "/vendor/lib/modules/android13-5.15_mi_sw_sync.ko:"
add_module_dep "/vendor/lib/modules/android13-5.15_moon_cache.ko:"
add_module_dep "/vendor/lib/modules/android13-5.15_moon_kshrink_lruvecd.ko:"
add_module_dep "/vendor/lib/modules/android13-5.15_moon_kshrink_slabd.ko:"
add_module_dep "/vendor/lib/modules/android13-5.15_moon_look_around.ko:"
add_module_dep "/vendor/lib/modules/android13-5.15_moon_mapped_protect.ko:"
echo -e "${Green}- vendor_dlkm分区添加内核模块成功添加${NC}"
End_Time vendor_dlkm分区添加内核模块
End_Time 内置水龙优化
##处理IMG文件
echo -e "${Red}- 开始处理IMG文件${NC}"
Start_Time
#去除vbmeta.img和vbmeta_system.img验证
echo -e "${Red}- 开始除vbmeta.img和vbmeta_system.img验证${NC}"
Start_Time
vbmeta_tool="$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification
for img in vbmeta vbmeta_system; do
    target="$GITHUB_WORKSPACE"/firmware/images/${img}.img
    if [ ! -f "$vbmeta_tool" ]; then
        echo -e "${Yellow}- 警告: 未找到vbmeta-disable-verification工具${NC}"
        break
    elif [ ! -f "$target" ]; then
        echo -e "${Yellow}- 警告: 未找到${img}.img，跳过${NC}"
    else
        if "$vbmeta_tool" "$target"; then
            echo -e "${Green}- ${img}.img验证去除成功${NC}"
        else
            echo -e "${Yellow}- ${img}.img验证去除失败，请检查${NC}"
        fi
    fi
done
End_Time 去除vbmeta.img和vbmeta_system.img验证
#init_boot.img修补KernelSU
echo -e "${Red}- 开始为init_boot.img修补KernelSU${NC}"
Start_Time
ksu_ok=1
export PATH="$GITHUB_WORKSPACE"/tools:$PATH
init_boot_img="$GITHUB_WORKSPACE"/firmware/images/init_boot.img
for f in "$init_boot_img" "$ksud" "$ksuinit" "$ksu_ko" "$magiskboot"; do
  [ -f "$f" ] || { echo -e "${Yellow}- 警告: 未找到修补所需相关文件: $f${NC}"; ksu_ok=0; }
done
if [ "$ksu_ok" -eq 1 ]; then
  chmod +x "$ksud" "$magiskboot"
  cp -f "$init_boot_img" "$init_boot_img.orig"  
  cd "$GITHUB_WORKSPACE" 
  if "$ksud" boot-patch --boot "$init_boot_img" --module "$ksu_ko" --init "$ksuinit"; then
      patched_img=$(find "$GITHUB_WORKSPACE" -maxdepth 1 -type f -name "*kernelsu*.img" | head -n 1)
      if [ -n "$patched_img" ]; then
          mv -f "$patched_img" "$init_boot_img"
      else
          echo -e "${Yellow}- 警告: 未找到修补后的init_boot.img${NC}"
          ksu_ok=0
      fi
  else
      ksu_ok=0
  fi 
  if [ "$ksu_ok" -eq 0 ] && [ -f "$init_boot_img.orig" ]; then
      cp -f "$init_boot_img.orig" "$init_boot_img"
  fi
  rm -f "$init_boot_img.orig"
fi
if [ "$ksu_ok" -eq 1 ]; then
  echo -e "${Green}- init_boot.img修补KernelSU完成${NC}"
else
  echo -e "${Yellow}- init_boot.img修补KernelSU失败，本次构建将使用官方init_boot.img${NC}"
fi
End_Time 为init_boot.img修补KernelSU
End_Time 处理IMG文件
#精简apk
echo -e "${Red}- 开始精简apk${NC}"
Start_Time
rm -rf "$GITHUB_WORKSPACE"/images/mi_ext/product/data-app/HsjPro
rm -rf "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore
rm -rf "$GITHUB_WORKSPACE"/images/product/app/HybridPlatform
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MiTrustService
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MIUIAccessibility
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MIUIgreenguard
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MIUISecurityInputMethod
rm -rf "$GITHUB_WORKSPACE"/images/product/app/SogouIME
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/BaiduIME
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/CAJLauncher
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/iFlytekIME
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIpayPad_NO_NFC
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIService
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MiShop
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIDuokanReaderPad
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIEmail
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIGameCenterPad
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIHuanji
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIMusicPAD
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUISecurityManager
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/Padapp
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/SmartHome
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/WpsLauncher
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/kidspace
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiGameCenterSDKService
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiniGameService
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MIUIBrowserPad
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/QuickSearchBoxPadMIUI15
End_Time 精简apk
End_Time 功能修复
###功能修复结束

###生成super.img
#生成$partition.img
echo -e "${Red}- 开始生成分区镜像${NC}"
Start_Time
partitions=("mi_ext" "odm" "product" "system" "system_dlkm" "system_ext" "vendor" "vendor_dlkm")
for partition in "${partitions[@]}"; do
echo -e "${Red}- 正在生成$partition${NC}"
Start_Time
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts None
    sudo $erofs_mkfs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$partition --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts "$GITHUB_WORKSPACE"/super/$partition.img "$GITHUB_WORKSPACE"/images/$partition
    eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/super/$partition.img | awk {'print $1'})
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
End_Time 生成${partition}.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/images/config
End_Time 生成分区镜像
echo -e "${Red}- 开始打包super.img${NC}"
Start_Time
  $lpmake --metadata-size 65536 --super-name super --block-size 4096 \
  --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a \
  --image mi_ext_a="$GITHUB_WORKSPACE"/super/mi_ext.img \
  --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a \
  --image odm_a="$GITHUB_WORKSPACE"/super/odm.img \
  --partition odm_b:readonly:0:qti_dynamic_partitions_b \
  --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a \
  --image product_a="$GITHUB_WORKSPACE"/super/product.img \
  --partition product_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a \
  --image system_a="$GITHUB_WORKSPACE"/super/system.img \
  --partition system_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a \
  --image system_dlkm_a="$GITHUB_WORKSPACE"/super/system_dlkm.img \
  --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a \
  --image system_ext_a="$GITHUB_WORKSPACE"/super/system_ext.img \
  --partition system_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a \
  --image vendor_a="$GITHUB_WORKSPACE"/super/vendor.img \
  --partition vendor_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a \
  --image vendor_dlkm_a="$GITHUB_WORKSPACE"/super/vendor_dlkm.img \
  --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b \
  --device super:11811160064 \
  --metadata-slots 3 \
  --group qti_dynamic_partitions_a:11811160064 \
  --group qti_dynamic_partitions_b:11811160064 \
  --virtual-ab -F \
  --output "$GITHUB_WORKSPACE"/super/super.img  
  for partition in "${partitions[@]}"; do
    rm -rf "$GITHUB_WORKSPACE"/super/$partition.img
  done
End_Time 打包super.img
###生成super.img结束

###生成完整刷机包
echo -e "${Red}- 开始生成完整刷机包${NC}"
Start_Time
#压缩super.img.zst
echo -e "${Red}- 开始压缩super.img.zst${NC}"
Start_Time
sudo find "$GITHUB_WORKSPACE"/super/ -exec touch -t 200901010000.00 {} \;
zstd -3 -f "$GITHUB_WORKSPACE"/super/super.img -o "$GITHUB_WORKSPACE"/firmware/images/super.img.zst --rm
End_Time 压缩super.img.zst
#生成ZIP刷机包
echo -e "${Red}- 开始生成ZIP刷机包${NC}"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/Sheng-HyperOS-${vendor_os_version}-CypressFjord.zip "$GITHUB_WORKSPACE"/firmware/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time 生成ZIP刷机包
#定制ROM包名
echo -e "${Red}- 开始定制ROM包名${NC}"
Start_Time
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/Sheng-HyperOS-${vendor_os_version}-CypressFjord.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="Sheng-HyperOS-${vendor_os_version}-CypressFjord-${zip_md5}.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/Sheng-HyperOS-${vendor_os_version}-CypressFjord.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
End_Time 定制ROM包名
End_Time 生成完整刷机包
###生成完整刷机包结束

End_Time 构建$device官改ROM
######构建$device官改ROM结束