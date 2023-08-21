## Disclaimer
This is a project I mostly did to learn more about Microsoft Azure and cloud infrastructure. There is better, cheaper, and easier ways to backup your home Linux system to the cloud. I personally use Backblaze B2 paired with Duplicati, as an amalgamation of these two blogposts: [blogpost 1](https://blogs.cornell.edu/classeit/2021/03/19/home-cloud-backup-for-linux/) [blogpost 2.](https://medium.com/@mormesher/building-your-own-linux-cloud-backup-system-75750f47d550) I do think this was a cool and fun project, and if you'd like to learn more about cloud concepts, everything in this guide will be entirely free.
## Summary of this Guide
In this guide I'm going to show you how to use Microsoft Azure (Microsoft's cloud computing platform) to set up a low powered virtual machine to connect to from your home computer, and automatically backup your data.
## Who This is For
This guide is not overly complicated. I think newbie computer users might have a hard time with this, but beginner to intermediate users should be fine.
# Overview
In this article I'm going to walk you through how to set up a system where you can back up your Linux system to the cloud, automatically, and incrementally. You can set up retention rules to maintain hourly, daily, weekly, and yearly backups as far back as you want. This system will scalable, and fairly cost-effective (around $20/month). We will use Rsync and hard links to minimize data transfer and drive space, and NFS to connect to our backup. Think of it like [Timeshift](https://github.com/linuxmint/timeshift) but for the cloud.
#### High Level How it Works
The way this system works is to use Microsoft Azure (their cloud computing platform) to create a virtual machine, and use Network File Sharing (NFS) to mount a folder from that VM to my local machine, and then use Rsync to create backups to that folder. I wrote a bash script to automatically backup my system, and to delete backups as they got older, but to keep around a few weekly and monthly backups.

I chose Microsoft Azure for a few reasons. For one, that's the platform I'm most familiar with, but also they were the cheapest option that I looked at. They allow creation of low end virtual "mechanical" hard drives. This is great because it keeps cost low. If I do need to recover large amounts of data quickly, I can just upgrade to a high-end SSD during the backup, and then downgrade back to an HDD afterwards. The cost for a 256GB backup ended up being around $18 a month. I only backup my `/home` directory because if I need to restore anything else, it's probably because I broke something, in which case I need to do a full system restore which would be extremely slow over the network, and a much better solution would be to use Timeshift.

***If you need to backup hundreds of GB of data, say for video production, this may not be the solution for you.***

Alright with all that out of the way, let's get into it.
## Microsoft Azure Setup
The first thing you're going to need to do is to create an Azure account. You can go [here](https://azure.microsoft.com/en-us) to create an account. Azure gives a $200 credit to new accounts to use within the first 90 days, so that essentially means your first 3 months of backup is free. 

### Virtual Machine Creation
#### Basics
Once you're in Azure, click on *'Create a Resource'*

![create-resource](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/bfeca667-d263-466e-8b72-31e9ea4b9044)

After that, choose *'Create'* under *'Virtual Machine'*

![vm-create 1](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/f27de425-d898-4d2d-ac70-d9ab7687be8a)

In the *'Basics'* tab, your Azure subscription should be selected, you can add this VM to a new resource group and name the VM and the resource group whatever you want. For region select whichever one is closest to you. 

For *Image* I selected Debian 11 as it's the OS I'm most familiar with. For the purpose of this guide, Debian or Ubuntu will be the easiest to follow, but any Linux distro will work, you might just have to look up the equivalent package names later.

For *Size* I chose *Standard_B1s - 1 vcpu, 1 GiB memory* as it's cheap, and I really don't need much more horsepower than this.

For *Authentication type* I chose SSH Public key as it's generally more secure.
For *SSH Public Key Source* I chose *Generate new key pair*, this means Azure will generate an SSH key for you to use to access the VM. The reason for the SSH key over password is that this will entirely disable anyone from trying to brute force into your machine. Granted if you use a strong and complicated password, they are highly unlikely to ever get it, but you don't want bots and hackers bogging down your network connection, and also why not just pick the more secure option?

For *Username* enter whatever usename you would like to use on the VM. In my case: *backup-user*

For *Inbound port rules* I chose *allow ssh*

![create-vm-basic 1](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/7c71aff2-33c8-49eb-913f-bbc2ce30771f)

After this, select *Next: Disks >*

#### Disks
On the *Disks* page:
For *OS Disk Type* select *Standard HDD* this will obviously be slower, but it will keep costs down

Deselect *Delete with VM*

Under *Data disks for {VM Name}* click *Create and attach a new disk*

![create-vm-disks 1](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/eb7284d5-6399-4823-aef3-e42653353528)

On this page click *change size*

![create-vm-create-new-disk](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/6a742677-8d7b-4f48-b356-2f01de3523c3)

Select *Standard HDD* for the storage type. The size of the disk is dependent on your needs. Do keep in mind however that Azure will only allow you to increase the size of a disk. So it's better to start small, and as it fills up increase the size. Once you're done here hit OK, and then *Next: Networking >*

![create-vm-select-disk-size](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/0c16ed45-73fb-4b37-b2e5-c2c345d9fbff)

#### Networking
This page is very important to the security of your VM. This VM will be outward facing the open Internet.  You don't want anybody to be able to go poking at it.

Under *NIC network security group* select *Advanced*
Under *Configure network security group* click *create new*.

![create-vm-networking](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/4f9b1db7-23b4-4757-940c-0d6f3c4c7359)

On this screen, right click and delete the default inbound rule that should be there. Then click *Add an inbound rule*

**This page is very important**. For the source, select IP Addresses. For some reason, at the time of writing, selecting *My IP Address* will show my current IP in the correct field, but when the rule is saved, it reverts to allowing *any* IP address. **This is bad**. Make sure you select *IP Addresses* from the *Source* drop down, and enter your home IP address into the *Source IP addresses* field. You can find your IP by searching "What's my IP".

*Source port ranges* should be left as an asterisk, and *Destination* can be left *Any*.

For *Service* select *Custom*

For *Destination port ranges* enter `22,111,2049`. Port 22 is for SSH. Port 111 and 2049 are for NFS. You could leave Destination port ranges as an asterisk, and you'll probably be fine considering only your home IP is allowed to connect, but principle of least privilege and all.
Change the priority to something low that isn't taken, add a name, and save the rule.

![create-vm-networking-nsg-rules](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/b30d97e6-b500-4e20-875f-f92437f5025d)

Once saved it should look something like this, with the black bar being your IP address:

![create-vm-networking-nsg-rules-done](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/c1b3eb32-26e8-4e28-83cd-d2b21a29ead8)

After this you can hit OK.

### Finish VM Creation
Click over to the *Monitoring* tab. In this tab just select *Enable recommended alert rules*. This isn't strictly necessary, but it will alert you if anything is funky with your VM.

![create-vm-monitoring](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/22c0eb4e-a0fd-4356-96b4-a46c953e58b7)

After this, you can hit *Review + Create*, and then *Create*. There should be a short wait while your VM gets created. At this point you should also get a download for your SSH key.

Once your VM is done being provisioned, on your Azure home screen you should see your new VM, disk and resource group. From the home page you can click on your VM.

![create-vm-complete](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/166d0d00-b00c-4ca6-81af-591ede505a09)

On this screen you can find the public IP for your new VM. Copy this into your clipboard and ssh into the VM from your local machine. use `-i` to specify the SSH key you were given.

![get-ip](https://github.com/ClaytonReardon/Custom-Cloud-Backup-for-Home-Linux-System/assets/112681383/d7a51b6f-bc80-4229-a9a9-bf7c4ec210e4)

```bash
ssh -i Backup-Server-Key.pem backup-user@<VM IP>
```
Congrats! You are now connected to your new backup server!
### Set up Network File Sharing (NFS)
#### On the VM Server
Now we need to set up NFS. This will allow us to mount a folder from the VM as if it were a folder on our local machine. On the VM, you need to install the NFS server package.
```bash
sudo apt install nfs-kernel-server
```
After this, enable and run the NFS service
```bash
sudo systemctl enable --now nfs-server
```
Next, create the folder on the VM you want to connect to from your local machine. For me, I created a folder called `Backups` in the home folder on the VM
```bash
mkdir ~/Backups
```
After that, we need to edit the `/etc/exports` file, which allow us to control what is being shared and with who. 
```bash
sudo vim /etc/exports
```

In this file, add this line, changing the Backups folder to whatever folder you created.
```
/home/backup-user/Backups		<YOUR LOCAL IP>(rw,async,no_subtree_check)
```
The `rw` option enables you to read and write to the share from your local machine. 

`Async` will speed up data transfer. `Async` allows the NFS server to violate NFS protocol and reply to requests before any changes made by that request have been committed to stable storage. Technically there is a chance of data loss if the VM crashes mid backup. However we are using hard mounting with our NFS share, which will just essentially pause the data transfer until the server comes back online. It seems unlikely that our minimal, Debian 11 Stable system will crash very often, so I chose to prioritize speed in this situation. *In a production enviroment handling very important data transfers, `async` should not be used.*

`No_subtree_check` tells the server not to perform any additional checks on the path within the host filesystem. This means that clients can access any directory within the exported file system, regardless of weather the client has permission to access the directories leading up the exported directory. This will slightly improve performance. In other scenarios, this can be a security risk, but in this case we're fine.

After editing `/etc/exports`, run
```bash
sudo exportfs -arv
```
#### On Your Local Machine
Now we need to mount that shared folder onto your local machine

First, ensure you have the NFS client software installed
```bash
sudo apt install nfs-common
```
After that, create a folder where you would like to mount the backup folder. For me I used
```bash
sudo mkdir /media/backup-server
```
Next, to mount the NFS share, run:
```bash
sudo mount -t nfs4 <VM IP>:/path/to/backup-folder /path/to/local/folder
# Example:
sudo mount -t nfs4 <VM IP>:/home/backup-user/Backups /media/backup-server
```
After this, you should be able to create a file on your VM, and see it on your local machine
```bash
touch /home/backup-user/Backups/test # On remote VM
ls /media/backup-server # On local machine
```
Once you've verified that this is successful, you can set up this mount to automatically happen on boot by editing your `/etc/fstab`.
```bash
sudo vim /etc/fstab
```
And then add this line to the bottom:
```bash
<VM IP>:/path/to/backup-folder  /path/to/local-folder  nfs4  defaults,user,exec
# Example:
<VM IP>:/home/backup-user/Backups     /media/backup-server    nfs4    defaults,user,exec
```
To verify this worked, first unmount the NFS share with:
```bash
sudo umount /path/to/local-folder
# Example:
sudo umount /media/backup-server
```
And then run:
```bash
sudo mount -a
```
This will mount all filesystems in fstab. Then verify the folder was mounted.
```bash
ls -la /media/backup-server
```

Great! You now have a folder from your remote VM mounted as if it is a local folder on your machine. This will make creating backups to it quite simple.
## Rsync
Rsync is the tool we will use to create backups. It will allow us to use hard links to minimize data transfer and disk space. Before we get started, a basic run down of hard-links:
#### Overview of Hard Links
All files stored on your computer are associated with an `inode`, the `inode` refers to a specific location on your hard drive where the data exists. When doing a normal copy/paste, the data is entirely copied and a new inode is created. With a hard link, a new file is created with the *same* inode as the old file. This means there will be 2 files on your system referring to the same location on your drive.

This is very useful in our situation because it allows us to create full snapshots of our home folder, but for the files that haven't changed, just use the same inode as in the past backup.

For example:
Say I create a backup one day of my entire home folder. Let's say my `.fonts` folder gets the `inode` `1000`. The next day when I create a backup, my `.fonts` folder hasn't changed at all, but instead of wasting resources copying the entire `.fonts` folder again, a hard link is created in the new backup with the same `inode` of `1000`. This means I have 2 separate snapshots of my home folder on 2 different days, but only the files that have changed will take up disk space!
#### Setting up Rsync
First off, make sure Rsync is installed on your system,
```bash
sudo apt install rsync
```
After that, let's do a test run of rsync. Let's backup a relatively smaller folder.
```bash
rsync -ravz ~/Documents /media/backup-server
```
`-r` will recursively backup into folders.
`-a` is 'archive' mode, it will preserve modification dates, permissions, attributes, etc. Basically, it backs up the folder exactly as it is.
`-v` is verbose mode.
`-z` will compress the data during backup, and then decompress it once the backup is done. Slightly speeds up performance.

Once this is done, check that your backup was successfully created on your VM
```bash
ls /media/backup-server

backup-user@Backup-Server:~/Backups$ ls
```
If so, congrats! It's time get into scripting.

#### Scripting the Backup
Here we need to create a script to automatically backup our home folder, use hard links, and also to delete backups after a certain amount of time. This is the script that I created:
```bash
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
```
###### Rsync
In this script we are running the `rsync` command to create a backup.

`"${src_dir}"` is the directory I want to backup, in this case, `/home/clayton`

`--partial` will keep partially transferred files. If the backup is interupted and must be restarted, rsync won't have to re-transfer files, and can pick up where it left of.

`--link-dest` tells `rsync` where to look to create hard links. In this case, every time a backup is created, the script creates a symlink to the most recent backup. The next time the script is run, `rsync` will look to this link to find the most recent backup.

`--exclude` tells `rsync` to exclude certain directories. In this case, I'm excluding my `.cache` and `trash` directories, but you can use this to exclude anything you don't want to backup.

`"${backup_name}"` is the name of the backup folder, in this case a timestamp.
###### Retention Rules
The next section is the retention rules. 

There is a function to extract the date from the directory name and convert it into a usable format.

For weekly retention: We check if there are other backups within the week range (from day 15 to day 168) that belong to the same week number. If so, we keep only the first one (with weekday = 1, i.e., Monday).

For monthly retention: We check if there are other backups within the month range (from day 169 to day 1080) that belong to the same month and year. If so, we keep only the first one (with day = 01).

The script now only removes backups older than 14 days which do not satisfy the weekly or monthly retention policy.

The final section is for creating a symlink to the latest backup. It removes the old symlink and creates a new symlink to the backup just made. Rsync will check this symlink the next time it runs to create hard links.

All that's left to do now is to set it up as a cron job
## Final Step, Automate It
Keep in mind that the first time you run this script, it will take awhile. Depending on how much data you have to backup, and how fast your internet is, it could take up to a few hours. After that first run however it will go much much quicker, as it will only have to backup whatever new files you created or edited that day.

You have 2 options here. You can either just run this script whenever is convenient, and move the script to a scratch pad and let it run in the background. Or you can set it up as a cron job to run every day at a certain time.
#### Cron Job
Cron Jobs are tasks scheduled to to run automatically at certain intervals.

Do not edit your cron jobs with sudo, that will edit the root user's cron jobs, which can be a security vulnerability. To edit your user's cron jobs:
```bash
crontab -e
```
The format for cron jobs, note that it uses 24 hour time format:
```bash
minute hour day-of-month month day-of-week task
```
So to run the script every day at noon for example you would enter:
```bash
0 12 * * * /path/to/your/script
```
To run it at 2:47 pm:
```
47 14 * * * /path/to/your/script
```
Just enter whatever interval you would like to run backups.

And that's it! You have now set up a system to automatically create incremental backups to your very own cloud server! Congratulations, and enjoy sleeping easy at night knowing that even if your house falls into a sink hole to the center of the earth, your data is safe!
