#!/bin/bash

set -e
set -u
set -o pipefail

CONFIG_FILE="/home/adrwal/praca-grid/linux-t1-t2/backup.conf"
LOCK_FILE="/home/adrwal/praca-grid/linux-t1-t2/backup.lock"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "${LOG_FILE}"
}

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "A script to create compressed backups with logging, rotation, and notifications."
    echo
    echo "Options:"
    echo "  -c, --config FILE      Path to a custom configuration file."
    echo "                         (Default: /home/adrwal/praca-grid/linux-t1-t2/backup.conf)"
    echo "  -s, --source DIR       Override the source directory specified in the config file."
    echo "  -d, --destination DIR  Override the backup destination directory."
    echo "  -h, --help             Display this help message and exit."
}

send_notification() {
    local subject="$1"
    local body="$2"
    echo "${body}" | mail -s "${subject}" "${EMAIL_TO}"
    log_message "Sent email notification to ${EMAIL_TO} with subject: ${subject}"
}

cleanup_exit() {
    log_message "Script finished. Removing lock file."
    if ! rm -f "${LOCK_FILE}"; then
        log_message "ERROR: Failed to remove lock file: ${LOCK_FILE}."
    fi
    exit $1
}


if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
    log_message "Configuration loaded from ${CONFIG_FILE}."
else
    log_message "FATAL: Configuration file not found at ${CONFIG_FILE}."
    send_notification "Backup FAILED: Configuration Missing" "The backup script could not find its configuration file at ${CONFIG_FILE}. Please restore it immediately."
    cleanup_exit 1
fi

if [ -e "${LOCK_FILE}" ]; then
    log_message "ERROR: Lock file exists. Another backup process may be running. Exiting."
    exit 1
else
    touch "${LOCK_FILE}"
    log_message "Lock file created. Starting backup process."
fi


while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            cleanup_exit 0
            ;;
        -c|--config)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                CONFIG_FILE="$2"
                shift
            else
                echo "Error: Argument for $1 is missing" >&2
                cleanup_exit 1
            fi
            ;;
        -s|--source)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                SOURCE_DIR="$2"
                shift
            else
                echo "Error: Argument for $1 is missing" >&2
                cleanup_exit 1
            fi
            ;;
        -d|--destination)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                BACKUP_DIR="$2"
                shift
            else
                echo "Error: Argument for $1 is missing" >&2
                cleanup_exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            cleanup_exit 1
            ;;
    esac
    shift
done

if [ ! -d "${SOURCE_DIR}" ]; then
    log_message "FATAL: Source directory ${SOURCE_DIR} does not exist."
    send_notification "Backup FAILED: Source Directory Missing" "The source directory ${SOURCE_DIR} could not be found. Backup aborted."
    cleanup_exit 1
fi

# Create backup directory if it doesn't exist
if ! mkdir -p "${BACKUP_DIR}"; then
    log_message "FATAL: Could not create backup directory ${BACKUP_DIR}."
    send_notification "Backup FAILED: Cannot Create Backup Directory" "The script failed to create the backup destination directory ${BACKUP_DIR}. Please check permissions."
    cleanup_exit 1
fi

# ACtual Backup Process
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
BACKUP_FILENAME="backup_${TIMESTAMP}.tar.gz"
BACKUP_FILE_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"
log_message "Starting backup of ${SOURCE_DIR} to ${BACKUP_FILE_PATH}."

if tar -czf "${BACKUP_FILE_PATH}" -C "$(dirname "${SOURCE_DIR}")" "$(basename "${SOURCE_DIR}")"; then
    BACKUP_SIZE=$(du -h "${BACKUP_FILE_PATH}" | cut -f1)
    log_message "SUCCESS: Backup created successfully. Size: ${BACKUP_SIZE}."

    # Clean Up Old Backups
    log_message "Cleaning up backups older than ${RETENTION_DAYS} days in ${BACKUP_DIR}..."
    DELETED_FILES=$(find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +"${RETENTION_DAYS}" -print -delete | wc -l)
    log_message "Cleanup complete. Deleted ${DELETED_FILES} old backup(s)."

    SUCCESS_BODY="Backup of ${SOURCE_DIR} completed successfully.

    Archive: ${BACKUP_FILE_PATH}
    Size: ${BACKUP_SIZE}
    Old backups deleted: ${DELETED_FILES}

    Log file is available at ${LOG_FILE}."
    log_message "$SUCCESS_BODY"
    send_notification "Backup SUCCESSFUL for ${SOURCE_DIR}" "${SUCCESS_BODY}"
else
    log_message "FATAL: tar command failed with exit code $?."
    rm -f "${BACKUP_FILE_PATH}"
    FAILURE_BODY="The backup of ${SOURCE_DIR} failed. The tar command exited with an error.

    Please check the log file for more details: ${LOG_FILE}"
    log_message "$FAILURE_BODY"
    send_notification "Backup FAILED for ${SOURCE_DIR}" "${FAILURE_BODY}"
    cleanup_exit 1
fi

cleanup_exit 0
