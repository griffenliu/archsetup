#!/bin/bash

#
# 注意: echo指令的 > 箭头为删除添加, >> 双箭头为文件末尾追加
# 声卡驱动安装 pulseaudio+alsa
# ALSA(高级Linux声音体系)是为声卡提供驱动的Linux内核组件,以替代原先的OSS(开放声音系统)
# PulseAudio是声音服务器,简单说,软件要发声就先发消息给声音服务器,然后声音服务器经过处理,然后发给驱动控制声音设备发出声音.
# 思源宋体 adobe-source-han-serif-cn-fonts
#

add_user_to_group() { #{{{
	local _user=${1}
	local _group=${2}

	if [[ -z ${_group} ]]; then
	  echo -e "ERROR! 'add_user_to_group' was not given enough parameters."
	  exit
	fi

	sudo groupadd ${_group}
	sudo gpasswd -a ${_user} ${_group}
	pid=$!;progress $pid
} #}}}

#VIDEO CARDS {{{
check_vga() { #{{{
	# Determine video chipset - only Intel, ATI and nvidia are supported by this script
	local _vga=`lspci | grep VGA | tr "[:upper:]" "[:lower:]"`
	local _vga_length=`lspci | grep VGA | wc -l`

	if [[ -n $(sudo dmidecode --type 1 | grep VirtualBox) ]]; then
	  echo Virtualbox
	  VIDEO_DRIVER="virtualbox"
	elif [[ -n $(sudo dmidecode --type 1 | grep VMware) ]]; then
	  echo VMware
	  VIDEO_DRIVER="vmware"
	elif [[ $_vga_length -eq 2 ]] && [[ -n $(echo ${_vga} | grep "nvidia") || -f /sys/kernel/debug/dri/0/vbios.rom ]]; then
	  echo Bumblebee
	  VIDEO_DRIVER="bumblebee"
	elif [[ -n $(echo ${_vga} | grep "nvidia") || -f /sys/kernel/debug/dri/0/vbios.rom ]]; then
	  echo Nvidia
	  read_input_text "Install NVIDIA proprietary driver" $PROPRIETARY_DRIVER
	  if [[ $OPTION == y ]]; then
		VIDEO_DRIVER="nvidia"
	  else
		VIDEO_DRIVER="nouveau"
	  fi
	elif [[ -n $(echo ${_vga} | grep "advanced micro devices") || -f /sys/kernel/debug/dri/0/radeon_pm_info || -f /sys/kernel/debug/dri/0/radeon_sa_info ]]; then
	  echo AMD/ATI
	  VIDEO_DRIVER="ati"
	elif [[ -n $(echo ${_vga} | grep "intel corporation") || -f /sys/kernel/debug/dri/0/i915_capabilities ]]; then
	  echo Intel
	  VIDEO_DRIVER="intel"
	else
	  echo VESA
	  VIDEO_DRIVER="vesa"
	fi
	OPTION="y"
	[[ $VIDEO_DRIVER == intel || $VIDEO_DRIVER == vesa ]] && read -p "Confirm video driver: $VIDEO_DRIVER [Y/n]" OPTION
	if [[ $OPTION == n ]]; then
	  read -p "Type your video driver [ex: sis, fbdev, modesetting]: " VIDEO_DRIVER
	fi
} #}}}
install_video_cards(){
  sudo pacman -S --noconfirm dmidecode
  check_vga
  #Virtualbox {{{
  if [[ ${VIDEO_DRIVER} == virtualbox ]]; then
	sudo pacman -S --noconfirm xf86-video-vesa
  #}}}
  #Bumblebee {{{
  elif [[ ${VIDEO_DRIVER} == bumblebee ]]; then
    XF86_DRIVERS=$(pacman -Qe | grep xf86-video | awk '{print $1}')
    [[ -n $XF86_DRIVERS ]] && pacman -Rcsn $XF86_DRIVERS
    pacman -S --needed xf86-video-intel bumblebee nvidia
    [[ ${ARCHI} == x86_64 ]] && pacman -S --needed lib32-virtualgl lib32-nvidia-utils
    replace_line '*options nouveau modeset=1' '#options nouveau modeset=1' /etc/modprobe.d/modprobe.conf
    replace_line '*MODULES="nouveau"' '#MODULES="nouveau"' /etc/mkinitcpio.conf
    mkinitcpio -p linux
    add_user_to_group ${username} bumblebee
  #}}}
  #NVIDIA {{{
  elif [[ ${VIDEO_DRIVER} == nvidia ]]; then
    XF86_DRIVERS=$(pacman -Qe | grep xf86-video | awk '{print $1}')
    [[ -n $XF86_DRIVERS ]] && pacman -Rcsn $XF86_DRIVERS
    pacman -S --needed nvidia{,-utils}
    [[ ${ARCHI} == x86_64 ]] && pacman -S --needed lib32-nvidia-utils
    replace_line '*options nouveau modeset=1' '#options nouveau modeset=1' /etc/modprobe.d/modprobe.conf
    replace_line '*MODULES="nouveau"' '#MODULES="nouveau"' /etc/mkinitcpio.conf
    mkinitcpio -p linux
    nvidia-xconfig --add-argb-glx-visuals --allow-glx-with-composite --composite -no-logo --render-accel -o /etc/X11/xorg.conf.d/20-nvidia.conf;
  #}}}
  #Nouveau [NVIDIA] {{{
  elif [[ ${VIDEO_DRIVER} == nouveau ]]; then
    is_package_installed "nvidia" && pacman -Rdds --noconfirm nvidia{,-utils}
    [[ ${ARCHI} == x86_64 ]] && is_package_installed "lib32-nvidia-utils" && pacman -Rdds --noconfirm lib32-nvidia-utils
    [[ -f /etc/X11/xorg.conf.d/20-nvidia.conf ]] && rm /etc/X11/xorg.conf.d/20-nvidia.conf
    package_install "xf86-video-${VIDEO_DRIVER} mesa-libgl libvdpau-va-gl"
    replace_line '#*options nouveau modeset=1' 'options nouveau modeset=1' /etc/modprobe.d/modprobe.conf
    replace_line '#*MODULES="nouveau"' 'MODULES="nouveau"' /etc/mkinitcpio.conf
    mkinitcpio -p linux
  #}}}
  #ATI {{{
  elif [[ ${VIDEO_DRIVER} == ati ]]; then
    is_package_installed "catalyst-total" && pacman -Rdds --noconfirm catalyst-total
    [[ -f /etc/X11/xorg.conf.d/20-radeon.conf ]] && rm /etc/X11/xorg.conf.d/20-radeon.conf
    [[ -f /etc/modules-load.d/catalyst.conf ]] && rm /etc/modules-load.d/catalyst.conf
    [[ -f /etc/X11/xorg.conf ]] && rm /etc/X11/xorg.conf
    package_install "xf86-video-${VIDEO_DRIVER} mesa-libgl mesa-vdpau libvdpau-va-gl"
    add_module "radeon" "ati"
  #}}}
  #Intel {{{
  elif [[ ${VIDEO_DRIVER} == intel ]]; then
    package_install "xf86-video-${VIDEO_DRIVER} mesa-libgl libvdpau-va-gl"
  #}}}
  #Vesa {{{
  else
    package_install "xf86-video-${VIDEO_DRIVER} mesa-libgl libvdpau-va-gl"
  fi
  #}}}
  if [[ ${ARCHI} == x86_64 ]]; then
    is_package_installed "mesa-libgl" && package_install "lib32-mesa-libgl"
    is_package_installed "mesa-vdpau" && package_install "lib32-mesa-vdpau"
  fi
  if is_package_installed "libvdpau-va-gl"; then
    add_line "export VDPAU_DRIVER=va_gl" "/etc/profile"
  fi
  pause_function
}
#}}}

add_cn_repo(){
	# http://repo.archlinuxcn.org/$arch 
	# https://mirrors.ustc.edu.cn/archlinuxcn/$arch [this is fast]
	if grep -Fxq "[archlinuxcn]" /etc/pacman.conf
	then
		echo china repo already exist, ignore...
	else
		sudo sh -c 'echo [archlinuxcn] >> /etc/pacman.conf'
		sudo sh -c 'echo Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch >> /etc/pacman.conf'
		sudo pacman -Sy --noconfirm archlinuxcn-keyring
		sudo pacman -Syy
		echo done...
	fi
}

other_softs(){
echo '======================================='
# 文件系统支持
#sudo pacman -S --noconfirm ntfs-3g dosfstools exfat-utils f2fs-tools fuse fuse-exfat autofs mtpfs

# openssh
#sudo pacman -S --noconfirm openssh
#sudo systemctl enable sshd
#sudo systemctl start sshd

# 电源管理
#sudo pacman -S --noconfirm tlp
#system_ctl enable tlp
#system_ctl enable tlp-sleep
#system_ctl disable systemd-rfkill
#tlp start

# 打印系统
#sudo pacman -S cups cups-filters ghostscript gsfonts
#sudo pacman -S gutenprint foomatic-db foomatic-db-engine foomatic-db-nonfree foomatic-filters foomatic-db-ppds foomatic-db-nonfree-ppds hplip splix cups-pdf foomatic-db-gutenprint-ppds
#sudo systemctl enable org.cups.cupsd.service
}

default_configs(){
	#.Xresources;xterm;rofi configs
	echo -e "!look and feel
xterm.termName: xterm-256color
!xterm.geometry: 80x36
xterm*scrollBar: false
xterm*rightScrollBar: true
xterm*loginshell: true
xterm*cursorBlink: true
xterm*background: black
xterm*foreground: gray
xterm.borderLess: true
xterm*colorUL: yellow
xterm*colorBD: white
!修正Alt不能正常使用的问题
xterm*eightBitInput: false
xterm*altSendsEscape: true
!拷贝屏幕内容，包含所有颜色控制符
!xterm*printAttributes: 2
!xterm*printerCommand: cat > ~/xtermdump
!快捷键定义：鼠标选择自动复制，ctrl-v粘贴，ctrl-p拷屏。鼠标中间是复制到xterm
XTerm*VT100.Translations: #override \
	<BtnUp>           : select-end(CLIPBOARD,PRIMARY,CUT_BUFFER0) \n\
	Ctrl <KeyPress> V : insert-selection(CLIPBOARD,PRIMARY,CUT_BUFFER0) \n\
	Ctrl <KeyPress> P : print() \n
!font and locale
xterm*locale: true
xterm.utf8: true
xterm*utf8Title: true
xterm*fontMenu*fontdefault*Label: Default
xterm*faceName: Monaco:antialias=True:pixelsize=16
xterm*faceNameDoublesize: Source Han Serif CN:pixelsize=14:antialias=True
!xterm*letterSpace: -1
xterm*xftAntialias: true
xterm*cjkWidth:false" > ~/.Xresources

	# i3 configs
	#mkdirs -p ~/.config/i3
	#cp /etc/i3/config ~/.config/i3/
	# auto start
	#sed -i "11a \
	#exec --no-startup-id volumeicon\n\
	#exec --no-startup-id feh --bg-scale ~/wall.jpg\n\
	#" ~/.config/i3/config
	# font
	#sed -i 's/^font pango:monospace 8/font pango:Misc Fixed,Source Han Serif CN 10/g' ~/.config/i3/config
	# starter
	#sed -i 's/^bindsym $mod+d exec dmenu_run/bindsym $mod+Shift+d exec dmenu_run\nbindsym $mod+d exec rofi -show drun/g' ~/.config/i3/config

	#create a xinitrc file in home user directory
	cp -fv /etc/X11/xinit/xinitrc ~/.xinitrc
	sed -i 's/^twm &/export LANG=zh_CN.UTF-8/g' ~/.xinitrc
	sed -i 's/^xclock -geometry 50x50-1+1 &/export LANGUAGE=zh_CN:en_US/g' ~/.xinitrc
	sed -i 's/^xterm -geometry 80x50+494+51 &/export LC_CTYPE=en_US.UTF-8/g' ~/.xinitrc
	# fcitx
	sed -i 's/^xterm -geometry 80x20+494-0 &/export GTK_IM_MODULE=fcitx/g' ~/.xinitrc
	sed -i 's/^exec xterm -geometry 80x66+0+0 -name login/export QT_IM_MODULE=fcitx/g' ~/.xinitrc
	sudo echo -e 'export XMODIFIERS="@im=fcitx"' >> ~/.xinitrc
	sudo echo -e "exec fcitx & exec i3" >> ~/.xinitrc
}

###############################################################################################################
# china mirror repo
add_cn_repo

# aur helper
sudo pacman -S --noconfirm yaourt

# tools
sudo pacman -S --noconfirm bash-completion dos2unix git wget vim htop neofetch net-tools
sudo pacman -S --noconfirm mlocate #finder
sudo pacman -S --noconfirm zip unzip unrar p7zip #压缩工具
# audio
sudo pacman -S --noconfirm alsa-utils alsa-plugins pulseaudio pulseaudio-alsa
# other
other_softs
# desktop
sudo pacman -S --noconfirm xorg-server xorg-xinit
# drivers
install_video_cards
# desktop soft
sudo pacman -S --noconfirm fcitx-im fcitx-configtool
sudo pacman -S --noconfirm xterm zathura galculator
# china font
sudo pacman -S --noconfirm adobe-source-han-serif-cn-fonts
yaourt -S ttf-monaco
# window manager
sudo pacman -S --noconfirm i3 dmenu rofi feh volumeicon
# configs
default_configs
# browser; other apps xmind
yaourt -S wiznote wps-office google-chrome

# virtualbox
#sudo pacman -S virtualbox virtualbox-host-dkms virtualbox-guest-iso linux-headers
#yaourt virtualbox-ext-oracle
#add_user_to_group ${username} vboxusers
#modprobe vboxdrv vboxnetflt




