#!/bin/bash

apt update -y
apt install --no-install-recommends --no-install-suggests -y \
    git build-essential debhelper libusb-1.0-0-dev pkg-config fakeroot \
    libncurses-dev zlib1g-dev libzstd-dev librtlsdr-dev help2man -y
git clone --depth 20 https://github.com/wiedehopf/readsb.git
cd readsb
export DEB_BUILD_OPTIONS=noddebs
rm -f ../readsb_*.deb
dpkg-buildpackage -b -ui -uc -us --build-profiles=rtlsdr
dpkg -i ../readsb_*.deb -y
cd /

cp readsb.defaults /etc/default/readsb

source /etc/default/readsb
/usr/bin/readsb $RECEIVER_OPTIONS $DECODER_OPTIONS $NET_OPTIONS $JSON_OPTIONS --write-json /run/readsb
