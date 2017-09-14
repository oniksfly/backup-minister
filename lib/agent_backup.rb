require_relative 'backup'
require 'yaml'
require 'logger'
require 'rubygems/package'
require 'tempfile'

CONFIG_FILE_NAME = 'config.yml'
DATABASE_DRIVERS = %i(docker)
LOGGER = Logger.new(STDOUT)

module Lib
    class AgentBackup < Backup
        @projects = nil
        @config_file_name = nil
    
        def initialize(file_name = nil)
            super
            load_projects(config)
        end
    
        # Get project configuration
        #
        # @param name: [Symbol] Project name
        # @param index: [Integer] Project index
        #
        # @return [Hash]
        def project_config(name: nil, index: nil)
            raise ArgumentError, 'At least one of arguments required' if name.nil? and index.nil?
            project_name = name.nil? ? @projects[index] : name.to_s
    
            if project_name and @config['projects'][project_name]
                @config['projects'][project_name]
            else
                raise ArgumentError, "No project #{name ? name : index} found."
            end
        end
    
        # Get setting item value
        #
        # @param [String] Settings name
        #
        # @return [Object, nil] return settings value if present
        def setting(name)
            result = nil
            if @config['settings'].nil?
                LOGGER.error 'Settings are empty'
            elsif @config['settings'][name].nil?
                LOGGER.error "Setting #{name} is missing."
            else
                @config['settings'][name]
            end
        end
    
        def backup_database(project_name)
            base_name = project_name + '_' + Time.new.strftime('%Y%m%d_%H%M')
            if project_config(name: project_name)['database'] 
                backup_file = make_database_backup(project_config(name: project_name)['database'], base_name)
                if backup_file.nil?
                    LOGGER.error "Can't create database backup for project #{project_name}."
                else
                    archive_and_remove_file("#{base_name}.tar.gz", backup_file)
                end
            else
                LOGGER.error "No database config found for #{project_name}."
            end
        end
    
        # Wrapper for `system` with check 
        def execute(command)
            system command
            code = $?.exitstatus
            LOGGER.warn "Failed to execute command `#{command}` with code #{code}." if code > 0
        end
        
        # Load projects list if exists
        def load_projects(config)
            if config['projects'].nil? or config['projects'].empty?
                LOGGER.warn 'No projects found. Nothing to do.'
            else
                @projects = config['projects'].keys
                LOGGER.info "Found projects: #{@projects.join(', ')}."
            end
        end
    
        # Generate database SQL backup file
        #
        # @param database_config [Hash] connection database settings
        # @param base_name [String] name for backup
        #
        # @return [File, nil] path to SQL file
        def make_database_backup(database_config, base_name, container_name = nil)
            raise ArgumentError, "Driver #{database_config['driver']} not supported." unless DATABASE_DRIVERS.include?(database_config['driver'])
    
            container_name = setting('database_container')
            if container_name 
                backup_file_name = base_name + '.sql'
                command = "docker exec -i #{container_name} pg_dump #{database_config['name']}"
                command += " -U#{database_config['user']}" if database_config['user']
                command += " > #{backup_file_name}"
                execute(command)
    
                if File.exist?(backup_file_name)
                    LOGGER.debug "Database backup file #{backup_file_name} created."
                    file = File.open(backup_file_name, 'r')
                    database_file_valid?(file) ? file : nil
                else
                    LOGGER.error "Can't create database backup file `#{backup_file_name}`."
                end
            else
                LOGGER.error 'Database container name is missing. Can\'t backup.'
            end
        end
    
        # Check basic content of SQL backup file
        #
        # @param file [File]
        #
        # @return [Boolean]
        def database_file_valid?(file)
            result = false
    
            if file.size
                LOGGER.debug "File #{file.path} is #{file.size} bytes."
                content = file.read
                if Regexp.new('(.)+(PostgreSQL database dump)(.)+(PostgreSQL database dump complete)(.)+', Regexp::MULTILINE).match(content).to_a.count >= 4
                    LOGGER.debug "File #{file.path} looks like DB dump."
                    result = true
                else
                    LOGGER.warn "File #{file.path} doesn't looks like DB dump."
                    result = false
                end
            else
                LOGGER.warn "File #{file.path} has 0 length or doesn't exists."
                result = false
            end
    
            result
        end
    
        # Create TAR GZ single file archive
        #
        # @param file_name [String] file name for new archive (including extension)
        # @param file [File] target file to archive
        def archive_file(file_name, file)
            target = Tempfile.new(file.path)
            Gem::Package::TarWriter.new(target) do |tar|
                file = File.open(file.path, 'r')
                tar.add_file(file.path, file.stat.mode) do |io| 
                    io.write(file.read)
                end
                file.close
            end
            target.close
                    
            base_dir = File.expand_path(File.dirname(file.path)) + '/'
            gz_file = Zlib::GzipWriter.open(base_dir + file_name) do |gz|
                gz.mtime = File.mtime(target.path)
                gz.orig_name = base_dir + file_name
                gz.write IO.binread(target.path)
            end
    
            gz_file
        ensure
            target.close if target and !target.closed?
        end
    
        # Create TAR GZ archive and delete original file
        # @see #archive_file for arguments description
        def archive_and_remove_file(file_name, file)
            archive_file(file_name, file)
            begin
                File.delete(file)
                LOGGER.log "File #{file.path} was deleted."
            rescue StandardError => error
                LOGGER.warn "Can't delete file #{file.path} with error: #{error}."
            end
        end
    end 
end