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
* **SHA-256:** `32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3`
