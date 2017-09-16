[![Gem Version](https://badge.fury.io/rb/backup_minister.svg)](https://badge.fury.io/rb/backup_minister)

# Backup Minister
Provide two sides method to backup data from docker containers to single remote server or set of servers.

## Requirements
* [Ruby](https://www.ruby-lang.org/en/documentation/installation/) (>= 2.0)

Gems will install:
* [net-ssh](https://github.com/net-ssh/net-ssh)
* [thor](http://whatisthor.com/)

## Installation

`gem install backup_minister`

May be `sudo` required for system-wide installation

## Usage
For database backup run on agent machine:
```bash
backup_minister backup_database --project_name=PROJECT_NAME_FROM_CONFIG
```

### Configuration

## Warranties
It's free but useless. Do not use it.