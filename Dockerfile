FROM debian:bookworm-slim

COPY install-script.sh install.sh
COPY start.sh start.sh
COPY readsb.sh readsb.sh
COPY wingbits.sh wingbits.sh
RUN chmod 755 *.sh

RUN mkdir run/readsb
RUN touch /run/readsb/aircraft.json.readsb_tmp
RUN touch /run/readsb/aircraft.binCraft.zst.readsb_tmp

RUN loc="0.0, 0.0" id="cool-color-animal" ./install.sh

ENTRYPOINT ["./start.sh"]
