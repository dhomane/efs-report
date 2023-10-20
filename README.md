# EFS Report and NFS Monitoring Script

This Bash script is designed for collecting diagnostic information related to Amazon Elastic File System (EFS) and monitoring Network File System (NFS) activity on a Linux system. It's particularly useful for diagnosing EFS and NFS-related issues. The script can be run as root or with elevated privileges to ensure comprehensive data collection.

## Table of Contents

- [Features](#features)
- [Usage](#usage)
- [Options](#options)
- [Installation](#installation)
- [Examples](#examples)
- [Impact](#impact)
- [Contributing](#contributing)
- [License](#license)

## Features

- Collects various system and NFS-related data, including NFS mounts, system statistics, and more.
- Monitors NFS timeouts for diagnostic purposes.
- Supports `rpcdebug` to enable logging for NFS or RPC issues.
- Organizes collected data into a compressed archive ready for upload to AWS Support.

## Usage

To use this script, follow the instructions below:

### Installation

1. Download or clone this repository to your Linux system.

2. Make the script executable:
   ```bash
   chmod +x efsreport.sh

## Options

The script provides several command-line options to customize its behavior:

    -t: Specify the mount target's IP address or DNS name.
    -d: Set the trace duration (use "forever" to run indefinitely).
    -l: Search for NFSv4 mounted file systems.
    -p: Define a temporary directory for data storage.
    -w: Monitor NFS timeouts.
    -r: Enable rpcdebug for NFS or RPC (options: NFS, RPC, ALL).
    -h: Display usage instructions.

## Examples

Here are some example usages:

bash

./efsreport.sh -t 172.31.5.159 -d 300
./efsreport.sh -t 172.31.5.159 -d forever
./efsreport.sh -t file-system-id -d 300 -p /var/tmp
./efsreport.sh -t file-system-id -w
./efsreport.sh -t file-system-id -r NFS
./efsreport.sh -t file-system-id -r RPC
./efsreport.sh -t file-system-id -r ALL
./efsreport.sh -l

Please refer to the script itself for more details on usage.
## Impact

    Data Collection: The script collects passive data, which should not significantly disrupt normal system operations. Some additional system load may be generated due to data collection.

    NFS Timeout Monitoring: Monitoring NFS timeouts with the -w option may increase network and processing activity during timeouts.

    rpcdebug: Enabling rpcdebug can increase logging, potentially filling up log files. It may have a minor impact on system performance due to increased logging.

    File I/O: The script writes collected data to a temporary directory, involving file I/O operations with minimal impact on system performance.

## Contributing

If you encounter issues or have suggestions for improvements, feel free to open an issue or create a pull request. Contributions are welcome.

## License

This script is licensed under the MIT License. See the LICENSE file for more details.

Disclaimer: This script is provided as-is and should be used with caution in production environments. It's primarily intended for diagnostic and monitoring purposes.
