# Custom Cloud Backups for your Home Linux System.
As a project to learn more about cloud infrastructure, I set up a system to backup my home Linux system to a virtual machine in Microsoft Azure cloud.
This is a guide on how to do that.

Do keep in mind there are better, cheaper ways to do this for your home Linux system. I personally use [Backblaze B2](https://www.backblaze.com/cloud-storage) paired with [Duplicati](https://www.duplicati.com/) to backup my home system. It's simple to set up, and is an amalgamation of these two blogposts: [Blog on backups with Rclone and Duplicati](https://blogs.cornell.edu/classeit/2021/03/19/home-cloud-backup-for-linux/). [Blog on backups with Backblaze B2](https://medium.com/@mormesher/building-your-own-linux-cloud-backup-system-75750f47d550)

**If you want to follow this guide to learn more about cloud concepts, everything will be completely free, as Azure has a $200 credit to new accounts, which will more than cover this project.**

## Overview of How it Works
A low powered Virtual Machine is created in Azure Cloud. Network File Sharing (NFS) is used to mount a remote folder from that VM to your local system as if it is a local folder. Rsync is then used to create backups to that folder.

The backups are incremental, meaning that your entire system is not backed up every time, only files that are new, or have changed are backed up.
The backups are in a "snapshot" format. Meaning that every backup contains the complete file structure of your system.
[Hard Links](https://www.redhat.com/sysadmin/linking-linux-explained) are used to create links to files from previous backup. This is to enable snapshot formatting and reduce disk space and network bandwidth.

Retention rules are in place to maintain (by default) daily backups for 2 weeks, weekly backups for 6 months, and monthly backups indefinately.

The process is automated by running a bash script as a cron job that runs through the whole process of creating the backup, deleting backups that do not satisfy retention rules, and creating a link to the newest backup.

## *Pay Close Attention to the Security Reccomendations*
Configuring this in a secure manner is not difficult, but if you neglect to do so, you will likely be exposing your entire system backups to the open internet. 
***That would be bad.***
