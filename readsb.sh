#!/bin/bash

source /etc/default/readsb
/usr/bin/readsb $RECEIVER_OPTIONS $DECODER_OPTIONS $NET_OPTIONS $JSON_OPTIONS --write-json /run/readsb --quiet
