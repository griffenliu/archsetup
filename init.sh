
### 两个问题：
### 1. 使用无线情况下难以配置网络
###    解决办法1：安装时使用wifi-menu -o命令生成netctl的配置文件，在安装完成核心后，退出arch-chroot将配置文件拷贝到/mnt/etc/netctl/文件夹中
###    启动后使用netctrl enable <profile_name>命令启用服务，再使用netctl start <profile_name>命令启动服务
###    解决办法2：在arch-chroot后，使用当前的网络安装dialog,wpa_supliant?等软件，以便重启后可以使用wifi-menu -o命令

### 2. 多显卡时需要一个鸟屎的bum?的貌似需要用户支持？

#!/usr/bin/bash


##############################################################
  contains_element() { #{{{
    #check if an element exist in a string
    for e in "${@:2}"; do [[ $e == $1 ]] && break; done;
  } #}}}
  invalid_option() { #{{{
    print_line
    echo "Invalid option. Try another one."
    pause_function
  } #}}}
  pause_function() { #{{{
    print_line
    if [[ $AUTOMATIC_MODE -eq 0 ]]; then
      read -e -sn 1 -p "Press enter to continue..."
    fi
  } #}}}
  arch_chroot() { #{{{
    arch-chroot $MOUNTPOINT /bin/bash -c "${1}"
  }
  print_line() { #{{{
    printf "%$(tput cols)s\n"|tr ' ' '-'
  } #}}}
  echo_info() {
	echo ""
	echo ">>>>> $1."
  }
##############################################################



# print command before executing, and exit when any command fails
#set -xe
# 显示所有磁盘列表
MOUNTPOINT="/mnt"
#选择磁盘设备 {{{
select_device(){
  devices_list=(`lsblk -d | awk '{print "/dev/" $1}' | grep 'sd\|hd\|vd\|nvme\|mmcblk'`);
  PS3="$prompt1"
  echo -e "Attached Devices:\n"
  lsblk -lnp -I 2,3,8,9,22,34,56,57,58,65,66,67,68,69,70,71,72,91,128,129,130,131,132,133,134,135,259 | awk '{print $1,$4,$6,$7}'| column -t
  echo -e "\n"
  echo -e "Select device to partition:\n"
  select device in "${devices_list[@]}"; do
    if contains_element "${device}" "${devices_list[@]}"; then
		break
    else
		invalid_option
    fi
  done
  BOOT_MOUNTPOINT=$device
}
umount_partitions(){
  echo_info "umount partitions"
  mounted_partitions=(`lsblk | grep ${MOUNTPOINT} | awk '{print $7}' | sort -r`)
  swapoff -a
  for i in ${mounted_partitions[@]}; do
    umount $i
  done
}
#}}}

### 检查网络，连接网络
echo_info "check network"
# 如果要使用wifi-menu配置网络，需要首先检测有线网络是否连通，如果联通，则忽略无线配置，否则检查无线网络设备名称，获取后使用wifi-menu进行设置
# wifi-menu


### 更新系统时间
echo_info "update system time"
timedatectl set-ntp true

### 建立并格式化硬盘分区
echo_info "create and format partition"
select_device
read -r -p "Is create and format partitions? [Y/n]" confirm
if [[ ! "$confirm" =~ ^(n|N) ]]; then

	# 选择分区方案:方案1:适合虚拟机;方案2:适合正式环境
	#parted -a opt ${device}
	#mkfs.ext4 ${device}1
	#mkfs.ext4 ${device}3
	#mkfs.ext4 ${device}4
	#mkswap ${device}2
	#swapon ${device}2
	### 挂载分区
	#echo_info "mount partitions"
	#mount ${device}3 /mnt
	#mkdir /mnt/boot
	#mkdir /mnt/home
	#mount ${device}1 /mnt/boot
	#mount ${device}4 /mnt/home
	
	partition_scheme_list=("virtualbox" "main" "ignore");
	PS3="please select partition scheme:"
	select PARTITION_SCHEME in "${partition_scheme_list[@]}"; do
		if contains_element "${PARTITION_SCHEME}" "${partition_scheme_list[@]}"; then
			break
		else
			invalid_option
		fi
	done
	
	if [[ ${PARTITION_SCHEME} != ignore ]]; then
		echo -n  'Please input your memory size(G):'
		read pc_memory
		if [[ ${PARTITION_SCHEME} == virtualbox ]]; then
			swap_endpos=$((100+$pc_memory*1024*2))
			echo " ### disk is ${device} ###"
			echo "|--------------------------------------------------|"
			echo "|${device}1 | /boot | 100M                         |"
			echo "|${device}2 | swap  | 2G                           |"
			echo "|${device}3 | /     | rest                         |"
			echo "|--------------------------------------------------|"
			echo "| $ parted -a opt ${device}                        |"
			echo "| > mklabel msdos                                  |"
			echo "| > mkpart primary ext4 1M 100M                    |"
			echo "| > set 1 boot on                                  |"
			echo "| > mkpart primary linux-swap 100M ${swap_endpos}M |"
			echo "| > mkpart primary ext4 ${swap_endpos}M -1         |"
			echo "| > p                                              |"
			echo "| > q                                              |"
			echo "|--------------------------------------------------|"
			parted ${device} -s -a optimal mklabel msdos mkpart primary ext4 1m 100M mkpart primary linux-swap 100M ${swap_endpos}M mkpart primary ext4 ${swap_endpos}M 100% set 1 boot on && \
			   mkfs.ext4 ${device}1 && mkfs.ext4 ${device}3 && mkswap ${device}2 && swapon ${device}2 && \
			   mount ${device}3 /mnt && mkdir /mnt/boot && mount ${device}1 /mnt/boot
		else
			swap_endpos=$((300+$pc_memory*1024))
			root_endpos=$(($swap_endpos+30*1024))
			echo " ### disk is ${device} ###"
			echo "|-------------------------------------------------------|"
			echo "|${device}1 | /boot | 100M-300M                         |"
			echo "|${device}2 | swap  | when <2G=memory*2; when>2G=memory |"
			echo "|${device}3 | /     | 15G-30G                           |"
			echo "|${device}4 | /home | the rest                          |"
			echo "|-------------------------------------------------------|"
			echo "| $ parted -a opt ${device}                             |"
			echo "| > mklabel msdos                                       |"
			echo "| > mkpart primary ext4 1M 300M                         |"
			echo "| > set 1 boot on                                       |"
			echo "| > mkpart primary linux-swap 300M ${swap_endpos}M      |"
			echo "| > mkpart primary ext4 ${swap_endpos}M ${root_endpos}M |"
			echo "| > mkpart primary ext4 ${root_endpos}M -1              |"
			echo "| > p                                                   |"
			echo "| > q                                                   |"
			echo "|-------------------------------------------------------|"
			parted ${device} -s -a optimal mklabel msdos mkpart primary ext4 1m 300M mkpart primary linux-swap 300M ${swap_endpos}M mkpart primary ext4 ${swap_endpos}M ${root_endpos}M mkpart primary ext4 ${root_endpos}M 100% set 1 boot on && \
			   mkfs.ext4 ${device}1 && mkfs.ext4 ${device}3 && mkfs.ext4 ${device}4 && mkswap ${device}2 && swapon ${device}2 && \
			   mount ${device}3 /mnt && mkdir /mnt/boot && mkdir /mnt/home && mount ${device}1 /mnt/boot && mount ${device}4 /mnt/home
		fi
	fi
fi




### 更新镜像列表
echo_info "update mirrorlist"
update_mirrorlist(){
  curl -sSL 'https://www.archlinux.org/mirrorlist/?country=CN&protocol=http&protocol=https&ip_version=4&use_mirror_status=on' | sed 's/^#Server/Server/g' | rankmirrors - > /etc/pacman.d/mirrorlist
}

while true; do
  update_mirrorlist
  cat /etc/pacman.d/mirrorlist
  read -r -p "Is this mirrorlist OK? [Y/n]" confirm
  if [[ ! "$confirm" =~ ^(n|N) ]]; then
    break
  fi
done

# 更新源
echo_info "update souces"
pacman -Syy

# 安装基本包
echo_info "install base packages"
pacstrap -i /mnt base base-devel --noconfirm

# 生成fstab
echo_info "generater fstab"
# 安装肯定是第一次的，确保生成新的fstab文件，所以先删除旧的文件，再生成新文件
rm -rf /mnt/etc/fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# 安装新系统 arch-chroot /mnt
# arch-chroot /mnt

# 时区
echo_info "set timezone"
arch_chroot "ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
arch_chroot "hwclock --systohc --utc"

# Locale
echo_info "set locale"
arch_chroot "sed -i 's/^#en_US.UTF-8/en_US.UTF-8/g' /etc/locale.gen"
arch_chroot "sed -i 's/^#zh_CN.UTF-8/zh_CN.UTF-8/g' /etc/locale.gen"
arch_chroot "locale-gen"
arch_chroot "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"

# 设置主机名
echo_info "set hostname"
hostname=griffenliu-arch
arch_chroot "echo '$hostname' > /etc/hostname"
arch_chroot "echo '127.0.1.1 $hostname.localdomain $hostname' > /etc/hosts"

# 新系统的网络配置？

#Initramfs
arch_chroot "mkinitcpio -p linux"

# 设置root密码
echo_info "set root password"
arch_chroot "passwd"

# 配置新用户以及sudo权限
username=lgf
arch_chroot "pacman -S --noconfirm  sudo"
# allow users of group wheel to use sudo
arch_chroot "sed -i 's/^# %wheel ALL=(ALL) ALL$/%wheel ALL=(ALL) ALL/' /etc/sudoers"
# Create regular user
arch_chroot "useradd -m -g users -G wheel -s /bin/bash $username"
arch_chroot "echo '$username:lgf' | chpasswd"
# 拷贝bashell配置文件到用户目录下
cp /etc/skel/.bashrc /home/$username/.bashrc
chown -R ${username}:users /home/${username}
echo_info "create user ${username}:lgf"

# 配置grub启动
echo_info "setup and config boot loader"
arch_chroot "pacman --noconfirm -S grub os-prober"
arch_chroot "grub-install --recheck $device"	# 将引导信息写到 sda
arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

# 如果是有线网络，在这里启用，无线网络将配置拷贝后，在这里启用，注意要安装配置工具
arch_chroot "systemctl enable dhcpcd"

if [[ "$?" == "0" ]]; then
  echo_info "Finished successfully"
  read -r -p "Reboot now? [Y/n]" confirm
  if [[ ! "$confirm" =~ ^(n|N) ]]; then
	umount_partitions
	reboot
  fi
fi