# CDR Report Tool

## Overview

This tool generates daily reports of Call Detail Record (CDR) processing counts for multiple services (Voice, SMS, GPRS, Recharge, Roaming). It scans CDR files (compressed or uncompressed), counts how many records of a given day were processed on subsequent days, and outputs formatted reports. The tool is highly configurable to adapt to different file formats (delimited or fixed‑width) and directory structures (fixed or flexible). It can be scheduled via cron with automatic retries on failure and includes an optional logging system.

## Features

- **Multi‑service support**: Separate configurations for each service (easily extendable).
- **Flexible field extraction**:
  - **Delimited fields** (e.g., pipe `|`, comma, whitespace) – specify separator and field index.
  - **Fixed‑width fields** – specify start position and length.
- **Configurable date format** inside CDR files (e.g., `%Y%m%d`, `%d/%m/%Y`).
- **Counts CDRs of a given day** that appear in directories of different processing days.
- **Supports both compressed (`.gz`) and uncompressed files** via the `COMPRESSED` flag.
- **Flexible directory paths** using templates: `{date}`, `{service}`, `{hour}` – no longer limited to `BASE_PATH/YYYYMMDD`.
- **Automatic logging** – set `LOG_FILE` to record every execution, retries, and errors.
- **Automatic output directory creation** (defaults to `./cdr_reports` relative to the script location, can be overridden).
- **Retry mechanism**: If report generation fails, the script retries up to `MAX_RETRIES` times with a `RETRY_DELAY` (default 1 hour) between attempts.
- **Success marker** in the report file to verify completion.
- **Easy cron integration** with a single command per service.
- **Lightweight**: Written in pure Bash (compatible with Bash 3.2+), uses standard tools (`find`, `zcat`/`cat`, `grep`, `awk`).

## Requirements

- **Bash** 3.2 or later (tested on 3.2.51).
- Standard Unix utilities: `date`, `find`, `xargs`, `zcat` (if `COMPRESSED=true`), `cat`, `grep`, `awk`, `mkdir`, `mv`, `sleep`.
- **Read access** to the CDR backup directories.
- **Write access** to `OUTPUT_DIR` and to the directory of `LOG_FILE` (if used).

## General configuration variables

Variable	        Description	                                                                        Required    Default
SERVICE_NAME	    Name of the service (used in report headers).	                                    Yes	        –
BASE_PATH	        Base path to backup directories (used only if PATH_TEMPLATE is not set).	        Yes*	    –
PATH_TEMPLATE	    Flexible path template (overrides BASE_PATH). Supports {date}, {service}, {hour}.	No	        –
FILE_PATTERN	    Pattern of files to process (e.g., *.gz, *).	                                    No	        *
OUTPUT_DIR	        Directory where reports will be stored.	                                            No	        ./cdr_reports
CDR_OFFSETS	        List of day offsets (relative to today) for which to report CDRs. Example: (-3 -2)	Yes	        –
PROC_OFFSETS_X	    For each CDR offset (absolute value <N>), list of processing day offsets to check.	Yes	        –
MAX_RETRIES	        Number of retry attempts on failure.                                                No	        3
RETRY_DELAY	        Delay in seconds between retries.	                                                No	        3600 (1 hora)
COMPRESSED	        true if files are gzipped, false for plain text.	                                No	        false
LOG_FILE	        Full path to log file. If set, automatic logging is enabled.	                    No	     (vacío, sin logs)
FIELD_SEPARATOR	    Delimiter character (e.g., |, ,, ). Used with DATE_FIELD_INDEX.	                    Yes**	    –
DATE_FIELD_INDEX    Field index (1‑based) that contains the date. Used with FIELD_SEPARATOR.	        Yes**	    –
DATE_FIELD_START    Start position (1‑based) for fixed‑width extraction. Used with DATE_FIELD_LENGTH.   Yes**	    –
DATE_FIELD_LENGTH   Length of the date field for fixed‑width extraction.                                Yes**	    –
DATE_FIELD_FORMAT   Format of the date inside the file (e.g., %Y%m%d, %d/%m/%Y).	                    Yes	        –
HOUR_RANGE	        List of values for {hour} in PATH_TEMPLATE (e.g., 00 01 02 ... 23).	                No	(se genera automático)

* BASE_PATH is required unless PATH_TEMPLATE is defined.
** You must use either FIELD_SEPARATOR + DATE_FIELD_INDEX or DATE_FIELD_START + DATE_FIELD_LENGTH.

## Understanding CDR_OFFSETS and PROC_OFFSETS_X

    CDR_OFFSETS: list of days (offsets from today) for which you want to see CDR counts.
    Example: (-3 -2) means you want reports for CDRs of 3 days ago and 2 days ago.

    PROC_OFFSETS_X: for each CDR offset (absolute value X), a list of processing day offsets (also relative to today) that should be searched for those CDRs.
    Example:

        PROC_OFFSETS_3="-3 -2 -1" means that for CDRs of 3 days ago, the script will look in the backup directories of 3 days ago, 2 days ago, and 1 day ago.

        PROC_OFFSETS_2="-2 -1" means for CDRs of 2 days ago, look in directories of 2 days ago and 1 day ago.

    Directory names are constructed as BASE_PATH/YYYYMMDD (traditional mode) or using PATH_TEMPLATE if defined.

Flexible path template syntax (PATH_TEMPLATE)

You can use the following placeholders, which are automatically replaced:

    {date} → processing date in YYYYMMDD format (e.g., 20260315).

    {service} → value of SERVICE_NAME.

    {hour} → each value from HOUR_RANGE (if not defined, 00 01 02 ... 23 is used).

Example:
    ```text
    PATH_TEMPLATE="/data/{date}/{service}/{hour}/backup"
    ```
This will generate paths like /data/20260315/voice/00/backup, /data/20260315/voice/01/backup, etc.
If the template does not contain {hour}, only one path per processing date is used.

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

## Output(report)

Reports are saved in OUTPUT_DIR (default ./cdr_reports) with the name cdr_report_<SERVICE_NAME>_<YYYYMMDD>.txt. Each report contains:

- A timestamp header.
- For each CDR day, a section with counts per processing day.
- A success marker at the end: ### REPORT COMPLETED SUCCESSFULLY ON ... ###.

## Automatic logging

If you set LOG_FILE in the configuration, the script will write entries like:
```text
[2026-03-18 10:30:45] [INFO] Starting report for service VOICE
[2026-03-18 10:30:46] [ERROR] Attempt 1 failed: exit code 1
[2026-03-18 10:30:46] [WARNING] Retrying in 3600 seconds...
[2026-03-18 11:30:46] [INFO] Report successfully generated: /var/log/cdr_reports/cdr_report_VOICE_20260318.txt
```
Log levels: INFO, WARNING, ERROR. The log is append‑only. You can rotate it externally with logrotate.

## Retry mechanism

If report generation fails (the generate_report function returns non‑zero), the script waits RETRY_DELAY seconds (default 3600) and tries again. After MAX_RETRIES attempts, it exits with an error. This handles transient failures (e.g., files not yet available, network issues) without human intervention.

The success marker at the end of the report file is written only if the generation completes without errors. The script checks the exit status of generate_report, which captures the success of the whole operation (including temporary file creation and final move).

## Troubleshooting

Configuration file not found: Verify the path or that the default file exists next to the script.

Field extraction not working:

    Check the first line of a sample CDR file: zcat /path/to/file.gz | head -n 1 (or cat if not compressed).

    Adjust FIELD_SEPARATOR / DATE_FIELD_INDEX or DATE_FIELD_START / DATE_FIELD_LENGTH accordingly.

    Ensure DATE_FIELD_FORMAT exactly matches the extracted string.

No files found:

    In traditional mode, the script only scans YYYYMMDD named subdirectories under BASE_PATH.

    In flexible mode, verify that the generated paths exist and contain files matching FILE_PATTERN.

Permission denied: Make sure the script has execute permission and the user has read access to CDR directories, and write access to OUTPUT_DIR and the LOG_FILE directory.

Retry loop – if the script keeps failing, inspect the error messages in the temporary file (printed to stderr) or in the log file. Also check the last report for the success marker.

Log not written: Ensure the parent directory of LOG_FILE exists and is writable. The script attempts to create it, but may fail due to permissions.

date -d issues on non‑GNU systems: If you use BSD/macOS, replace date -d with date -j -v-3d +%Y%m%d. The script assumes a standard Linux environment.

Bash 3.x compatibility: The script uses indexed arrays and dynamic variable names (PROC_OFFSETS_X) to work with older Bash versions (e.g., 3.2). It does not use associative arrays.

## Maintenance and logs

- The script automatically logs if LOG_FILE is set. Use logs to monitor failures and performance.
- To rotate logs, configure logrotate with a file like:
    ```text
    /var/log/cdr_reports/*.log {
        daily
        rotate 30
        compress
        delaycompress
        missingok
        notifempty
    }
    ```
- Schedule the script in cron (e.g., hourly) to get periodic reports. Use absolute paths in the configuration.
- Periodically clean up old reports from OUTPUT_DIR if needed.