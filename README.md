# CDR Report Tool

## Overview

This tool generates daily reports of Call Detail Record (CDR) processing counts for multiple services (Voice, SMS, GPRS, Recharge, Roaming). It scans CDR files (compressed or uncompressed), counts how many records of a given day were processed on subsequent days, and outputs formatted reports. The tool is highly configurable to adapt to different file formats (delimited or fixed-width) and can be scheduled via cron with automatic retries on failure.

## Features

- **Multi-service support**: Separate configurations for each service (easily extendable).
- **Flexible field extraction**:
  - **Delimited fields** (e.g., pipe `|`, comma, whitespace) – specify separator and field index.
  - **Fixed-width fields** – specify start position and length.
- **Configurable date format** in the CDR files (e.g., `%Y%m%d`, `%d/%m/%Y`).
- **Counts CDRs of a given day** that appear in directories of different processing days.
- **Supports both compressed and uncompressed files** via `COMPRESSED` flag (`true` for `.gz`, `false` for plain text).
- **Automatic output directory** creation (defaults to `./cdr_reports` relative to the script location, can be overridden).
- **Retry mechanism**: If report generation fails, the script retries up to 3 times with a 1‑hour delay between attempts.
- **Success marker** in the report file to verify completion.
- **Easy cron integration** with a single command per service.
- **Lightweight**: Written in pure Bash, uses standard tools (`find`, `zcat`/`cat`, `awk`).

## Requirements

- **Bash** 3.2 or later (tested on 3.2.51).
- Standard Unix utilities: `date`, `find`, `xargs`, `zcat` (if compressed), `cat` (if uncompressed), `awk`, `mkdir`, `mv`, `sleep`.
- **Access** to the CDR backup directories (read permissions).

## Installation

1. Clone the repository:
   ```bash
   git clone https://gitlab.etecsa.cu/beatriz.ontivero/cdr-report-tool.git
   cd cdr-report-tool
   ```

## General configuration variables

Variable	Description	Required	Default
SERVICE_NAME	Name of the service (used in report headers).	Yes	–
BASE_PATH	Path to the backup directory for the service (e.g., /fileser/.../voice/backup).	Yes	–
FILE_PATTERN	Pattern of files to process (e.g., *.gz, *).	No	*
OUTPUT_DIR	Directory where reports will be stored.	No	./cdr_reports
CDR_OFFSETS	List of day offsets (negative) for which to report CDRs. Example: (-3 -2).	Yes	–
PROC_OFFSETS	Associative array mapping a CDR offset to the list of processing day offsets to check.	Yes	–
MAX_RETRIES	Number of retry attempts on failure.	No	3
RETRY_DELAY	Delay in seconds between retries.	No	3600 (1 hour)

## Understanding CDR_OFFSETS and PROC_OFFSETS

    CDR_OFFSETS: List of days (as offsets from today) for which you want to see CDR counts. For example, (-3 -2) means you want reports for CDRs of 3 days ago and 2 days ago.

    PROC_OFFSETS: For each CDR day offset, a list of processing day offsets (also relative to today) that should be searched for those CDRs. For example:

        PROC_OFFSETS[-3]="-3 -2 -1" means that for CDRs of 3 days ago, the script will look in the backup directories of 3 days ago, 2 days ago, and 1 day ago (i.e., whether those CDRs were processed on those days).

        The actual directory names are constructed as BASE_PATH/YYYYMMDD where YYYYMMDD is the date computed from today + offset.

## Usage
Basic execution

Run the script with a configuration file:
```bash
./reporte_cdr.sh /path/to/config.conf
```

If you place the config file next to the script with the same base name (e.g., reporte_cdr.conf), you can run it without arguments:
Run the script with a configuration file:
```bash
./reporte_cdr.sh
./reporte_cdr.sh /path/to/config.conf
```

Using create_service_script:
```bash
./create_service_script.sh service-name /path/to/config.conf
```

Executing service script:
```bash
./reporte_service.sh > /path/to/log/service.log 2>&1 &
```

## Output

Reports are saved in the configured OUTPUT_DIR (default ./cdr_reports) with the name cdr_report_<SERVICE_NAME>_<YYYYMMDD>.txt. Each report contains:

- A timestamp header.
- For each CDR day, a section with counts per processing day.
- A success marker at the end.

## Retry mechanism

If the report generation fails (the generate_report function returns non‑zero), the script will wait RETRY_DELAY seconds (default 3600) and try again. After MAX_RETRIES attempts, it exits with an error. This ensures that transient failures (e.g., temporary network issues, files not yet available) are handled without human intervention.

The success marker at the end of the report file is written only if the generation completes without errors. The script checks the exit status of the generate_report function, which in turn captures the success of the entire operation, including the creation of the temporary file and the final move.

## Troubleshooting

- Configuration file not found: Ensure the path is correct or that the default file exists next to the script.
- Field extraction not working:
    - Check the first line of a sample CDR file: zcat /path/to/file.gz | head -n 1
    - Adjust FIELD_SEPARATOR / DATE_FIELD_INDEX or DATE_FIELD_START / DATE_FIELD_LENGTH accordingly.
    - Verify DATE_FIELD_FORMAT matches exactly the extracted string.
- No files found: The script only scans the exact date‑named subdirectories under BASE_PATH. Ensure they exist and contain files matching FILE_PATTERN.
- Permission denied: Make sure the script has execute permission and the user running it has read access to the CDR directories.
- Retry loop: If the script repeatedly fails, check the error messages in the temporary file (printed on stderr). You can also inspect the last generated report for the success marker.
