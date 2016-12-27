# BorgBackup automation scripts

This is a set of [BorgBackup](http://borgbackup.readthedocs.io) automation scripts I've deployed for making backups of live systems. 

The basic idea and a starting point for this comes from very nice script: https://gist.github.com/dschense/e55167d8915eb48d6eb3c42cb4d5137d

**This is WORK IN PROGRESS - it's an early version but already deployed, and it's published as an example for using Borg. This may become a complete solution one day, but don't expect it will ever be**

If you have any comments, please do it, I'm also accepting PRs. 

Please observe that there might be some local paths or other system specific configuration elements left.

## Architecture

This set of scripts is dedicated for client-server architecture with central backup server and multiple clients making remote backups over
ssh connections. 

### Convention

All the local backup related variables are named ```BORGLOCAL_*``` to be distinguished from environment variables used by Borg (```BORG_*```).

## Server

Server has to have a borg installed (we're using borg serve), and one mount path dedicated for backups. Backup is done using non-root user (borg). 

## Clients

All the repos are in keyfile mode. This is hardcoded for now. 
