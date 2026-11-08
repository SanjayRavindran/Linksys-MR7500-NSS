# Aquantia AQR114C PHY Firmware

The Linksys MR7500 5GbE WAN port uses the Marvell/Aquantia AQR114C-B0 multi-gigabit PHY.
To enable multi-gigabit link negotiation, the firmware blob `AQR114C.cld` must be placed here:

    files/lib/firmware/marvell/AQR114C.cld

### Automatic Extraction:
Run the extraction script to download the official stock Linksys firmware and extract the firmware blob automatically:

    ./scripts/extract_stock_blobs.sh

### Verification:
* **Filename:** `AQR114C.cld`
* **Size:** `393,218` bytes (v5.6.5 Cybertan Divo)
* **SHA-256:** `8a0e88cf738a0b07e602495d43be6c13fe6272551527efd04b6df00d3cb12eb6`
