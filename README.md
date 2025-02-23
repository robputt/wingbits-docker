# wingbits-docker
Builds container images for running Wingbits nodes (https://wingbits.com/) containerised.

## Supported Architectures
* amd64
* arm64/v8
* arm/v7

## Required Hardware
* Some form of computer, e.g. a single board computer like a Raspberry Pi 4
* A RTL SDR USB Dongle - I use one of these - https://www.amazon.co.uk/Nooelec-NESDR-SMArt-SDR-R820T2-Based/dp/B01HA642SW
* A Wingbits Geosigner USB Dongle - https://shop.wingbits.com/products/wingbits-geosigner
* A 1090Mhz antenna (preferably placed outside with a clear view of the sky) - https://shop.wingbits.com/products/wingbits-6dbi-ads-b-antenna-1090-mhz

## Run Container
1. Install docker - https://docs.docker.com/engine/install/
2. Clone the repo and use the sample docker-compose.yml file...

```bash
git clone https://github.com/robputt/wingbits-docker.git
cd wingbits-docker
docker compose up
```
