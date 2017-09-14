#!/usr/bin/env ruby

require_relative 'lib/agent_backup'

i = Lib::AgentBackup.new
i.backup_database('supply_staging')