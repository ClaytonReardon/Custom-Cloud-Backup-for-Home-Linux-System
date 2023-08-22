#!/bin/bash

# Script to backup to Azure VM
# Uses Rsync to backup to remote folder mounted locally with NFS
# Make sure remote folder is mounted before running script
# Best to add mount to /etc/fstab

src_dir="/home/clayton/"     # The directory to be backed up
backup_dir="/media/backup-server"   # Make sure this folder exists locally connected with NFS to VM:~/Backups
date="$(date '+%b-%d-%Y_%I:%M%p')"  # Timestamp format for backups: Aug-15-2023_1:16AM
backup_name="${backup_dir}/${date}" # Backup Folder Name
latest_link="${backup_dir}/latest"  # Name for the link to the latest backup

# Run rsync to create a backup
rsync --partial -ravz \
  "${src_dir}" \
  --link-dest "${latest_link}" \
  --exclude=".cache" \
  --exclude=".local/share/Trash" \
  "${backup_name}"

# Retention Rules
# Function to extract date from directory name and convert it usable format
get_proper_date() {
    local dir_date="$1"
    echo "${dir_date:0:11}" | xargs -I {} date -d "{}" +"%Y-%m-%d"
}

# Remove backups older than 14 days that aren't weekly or monthly backups
find "${backup_dir}" -maxdepth 1 -type d -name "???-??-????_*" -ctime +14 -print0 | while IFS= read -r -d '' dir; do
    dir_date=$(basename "${dir}")
    parsed_date=$(get_proper_date "${dir_date}")
    day=$(date -d "${parsed_date}" '+%d')
    week_day=$(date -d "${parsed_date}" '+%u')
    week_number=$(date -d "${parsed_date}" '+%U')
    month=$(date -d "${parsed_date}" '+%m')
    year=$(date -d "${parsed_date}" '+%Y')
    
    # Weekly backups for the past 6 months (168 days from current)
    if [[ $(find "${backup_dir}" -maxdepth 1 -type d -name "???-??-????_*" -ctime +14 -ctime -168 -print0 | xargs -0 -I {} bash -c 'echo $(get_proper_date "$(basename "{}")")' | xargs -I {} date -d "{}" "+%U" | grep -c "^${week_number}$") -gt 1 ]] && [[ ${week_day} -ne 1 ]]; then
        rm -r "${dir}"
    fi

    # Monthly backups for the past 3 years (1080 days from current)
    if [[ $(find "${backup_dir}" -maxdepth 1 -type d -name "???-??-????_*" -ctime +168 -ctime -1080 -print0 | xargs -0 -I {} bash -c 'echo $(get_proper_date "$(basename "{}")")' | xargs -I {} date -d "{}" "+%m-%Y" | grep -c "^${month}-${year}$") -gt 1 ]] && [[ ${day} -ne 01 ]]; then
        rm -r "${dir}"
    fi
done

# Remove link to old latest backup and create new one
 rm -rf "${latest_link}"
 ln -s "${backup_name}" "${latest_link}"
