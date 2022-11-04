#!/bin/bash
{
. /boot/dietpi/func/dietpi-globals

G_AGUP
G_AGDUG

# Build deps
G_AGI make gcc libc6-dev libasound2-dev libflac-dev libmad0-dev libvorbis-dev libmpg123-dev libavformat-dev libsoxr-dev liblirc-dev libfaad-dev libssl-dev libopus-dev

G_DIETPI-NOTIFY 2 'Downloading source code...'
G_EXEC cd /tmp
G_EXEC curl -sSfLO 'https://github.com/ralph-irving/squeezelite/archive/master.tar.gz'
[[ -d 'squeezelite-master' ]] && G_EXEC rm -R squeezelite-master
G_EXEC tar xf master.tar.gz
G_EXEC rm master.tar.gz
G_DIETPI-NOTIFY 2 'Compiling binary...'
G_EXEC cd squeezelite-master
G_EXEC_OUTPUT=1 G_EXEC make CFLAGS='-g0 -O3' OPTS='-DDSD -DFFMPEG -DRESAMPLE -DVISEXPORT -DLINKALL -DIR -DUSE_SSL'
G_EXEC strip --remove-section=.comment --remove-section=.note squeezelite

G_DIETPI-NOTIFY 2 'Starting packaging...'

# Dependencies based on distro version
adeps=('libc6' 'libasound2' 'libflac8' 'libmad0' 'libvorbisfile3' 'libmpg123-0' 'libsoxr0' 'liblirc-client0' 'libfaad2' 'libopus0')
case $G_DISTRO in
	[56]) adeps+=('libavformat58' 'libssl1.1');;
	7) adeps+=('libavformat59' 'libssl3');;
	*) G_DIETPI-NOTIFY 1 "Unsupported distro version: $G_DISTRO_NAME (ID=$G_DISTRO)"; exit 1;;
esac

# - Obtain DEB dependency versions
DEPS_APT_VERSIONED=
for i in "${adeps[@]}"
do
	DEPS_APT_VERSIONED+=" $i (>= $(dpkg-query -Wf '${VERSION}' "$i")),"
done
DEPS_APT_VERSIONED=${DEPS_APT_VERSIONED%,}
# shellcheck disable=SC2001
grep -q 'raspbian' /etc/os-release && DEPS_APT_VERSIONED=$(sed 's/+rp[it][0-9]\+[^)]*)/)/g' <<< "$DEPS_APT_VERSIONED") || DEPS_APT_VERSIONED=$(sed 's/+b[0-9]\+)/)/g' <<< "$DEPS_APT_VERSIONED")

# Package dir
G_EXEC cd /tmp
grep -q 'raspbian' /etc/os-release && DIR='squeezelite_armv6l' || DIR="squeezelite_$G_HW_ARCH_NAME"
G_EXEC rm -Rf "$DIR"
G_EXEC mkdir -p "$DIR/"{DEBIAN,lib/systemd/system,etc/default,usr/{bin,share/doc/squeezelite,share/man/man1}}
# - Binary
G_EXEC cp squeezelite-master/squeezelite "$DIR/usr/bin/"
# - man page
# shellcheck disable=SC2016
G_EXEC eval 'gzip -c squeezelite-master/doc/squeezelite.1 > $DIR/usr/share/man/man1/squeezelite.1.gz'
# - Copyright
G_EXEC cp squeezelite-master/LICENSE.txt "$DIR/usr/share/doc/squeezelite/copyright"
# - Environment file
cat << '_EOF_' > "$DIR/etc/default/squeezelite"
# Squeezelite command-line arguments: https://ralph-irving.github.io/squeezelite.html
ARGS='-W -C 5 -n DietPi-Squeezelite'
_EOF_
# - systemd service
cat << '_EOF_' > "$DIR/lib/systemd/system/squeezelite.service"
[Unit]
Description=Squeezelite (DietPi)
Documentation=man:squeezelite(1) https://ralph-irving.github.io/squeezelite.html
After=sound.target

[Service]
User=squeezelite
EnvironmentFile=/etc/default/squeezelite
ExecStart=/usr/bin/squeezelite $ARGS

[Install]
WantedBy=multi-user.target
_EOF_
# - postinst
cat << '_EOF_' > "$DIR/DEBIAN/postinst"
#!/bin/sh
if [ -d '/run/systemd/system' ]
then
	if getent passwd squeezelite > /dev/null
	then
		echo 'Configuring Squeezelite service user ...'
		usermod -aG audio -d /nonexistent -s /usr/sbin/nologin squeezelite
	else
		echo 'Creating Squeezelite service user ...'
		useradd -rMU -G audio -d /nonexistent -s /usr/sbin/nologin squeezelite
	fi

	echo 'Configuring Squeezelite systemd service ...'
	systemctl unmask squeezelite
	systemctl enable --now squeezelite
fi
_EOF_
# - prerm
cat << '_EOF_' > "$DIR/DEBIAN/prerm"
#!/bin/sh
if [ "$1" = 'remove' ] && [ -d '/run/systemd/system' ] && [ -f '/lib/systemd/system/squeezelite.service' ]
then
	echo 'Deconfiguring Squeezelite systemd service ...'
	systemctl unmask squeezelite
	systemctl disable --now squeezelite
fi
_EOF_
# - postrm
cat << '_EOF_' > "$DIR/DEBIAN/postrm"
#!/bin/sh
if [ "$1" = 'purge' ]
then
	if [ -d '/etc/systemd/system/squeezelite.service.d' ]
	then
		echo 'Removing Squeezelite systemd service overrides ...'
		rm -Rv /etc/systemd/system/squeezelite.service.d
	fi

	if getent passwd squeezelite > /dev/null
	then
		echo 'Removing Squeezelite service user ...'
		userdel squeezelite
	fi

	if getent group squeezelite > /dev/null
	then
		echo 'Removing Squeezelite service group ...'
		groupdel squeezelite
	fi
fi
_EOF_
G_EXEC chmod +x "$DIR/DEBIAN/"{postinst,prerm,postrm}
# - conffiles
echo '/etc/default/squeezelite' > "$DIR/DEBIAN/conffiles"
# - md5sums
find "$DIR" ! \( -path "$DIR/DEBIAN" -prune \) -type f -exec md5sum {} + | sed "s|$DIR/||" > "$DIR/DEBIAN/md5sums"
# - control
cat << _EOF_ > "$DIR/DEBIAN/control"
Package: squeezelite
Version: $(mawk -F\" '/MAJOR_VERSION/{print $2;exit}' squeezelite-master/squeezelite.h).$(mawk -F\" '/MINOR_VERSION/{print $2;exit}' squeezelite-master/squeezelite.h)-$(mawk -F\" '/MICRO_VERSION/{print $2;exit}' squeezelite-master/squeezelite.h)-dietpi1
Architecture: $(dpkg --print-architecture)
Maintainer: MichaIng <micha@dietpi.com>
Date: $(date '+%a, %d %b %Y %T %z')
Standards-Version: 4.6.1.1
Installed-Size: $(du -sk "$DIR" | mawk '{print $1}')
Depends:$DEPS_APT_VERSIONED
Conflicts: squeezelite-pa, squeezelite-pulseaudio
Section: sound
Priority: optional
Homepage: https://github.com/ralph-irving/squeezelite
Vcs-Git: https://github.com/ralph-irving/squeezelite.git
Vcs-Browser: https://github.com/ralph-irving/squeezelite
Description: lightweight headless Squeezebox emulator - ALSA version
 Squeezelite is a small headless Squeezebox emulator. It is aimed at
 supporting high quality audio including USB DAC based output at multiple
 sample rates.
 .
 It supports decoding PCM (WAV/AIFF), FLAC, MP3, Ogg, AAC, WMA and ALAC
 audio formats. It can also resample audio, which allows squeezelite to
 upsample the output to the highest sample rate supported by the output
 device.
 .
 This package is built with the resampling, ffmpeg and SSL options.
 It uses ALSA for audio output.
_EOF_
G_CONFIG_INJECT 'Installed-Size: ' "Installed-Size: $(du -sk "$DIR" | mawk '{print $1}')" "$DIR/DEBIAN/control"
# - Build
[[ -f $DIR.deb ]] && G_EXEC rm -R "$DIR.deb"
G_EXEC_OUTPUT=1 G_EXEC dpkg-deb -b "$DIR"
G_EXEC rm -R "$DIR"

exit 0
}