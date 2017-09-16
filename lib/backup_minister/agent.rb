require 'yaml'
require 'rubygems/package'
require 'tempfile'

CONFIG_FILE_NAME = 'config.yml'
DATABASE_DRIVERS = %i(docker)

class BackupMinister::Agent < BackupMinister
  @projects = nil
  @config_file_name = nil
  @remote_server_connection = nil

  def initialize(file_name = nil)
    super
    load_projects(config)
  end

  # Get setting item value
  #
  # @param name [String] Settings name
  #
  # @return [Object, nil] return settings value if present
  def setting(name)
    if @config['settings'].nil?
      LOGGER.error 'Settings are empty'
    elsif @config['settings'][name].nil?
      LOGGER.error "Setting #{name} is missing."
    else
      @config['settings'][name]
    end
  end

  # Create TAR GZ archive with database backup
  #
  # @param project_name [String]
  #
  # @return [String, nil]
  def backup_database(project_name)
    base_name = project_name + '_' + Time.new.strftime('%Y%m%d_%H%M')
    if project_config(name: project_name)['database']
      backup_file = make_database_backup(project_config(name: project_name)['database'], base_name)
      if backup_file.nil?
        LOGGER.error "Can't create database backup for project #{project_name}."
      else
        archive_file_name = archive_and_remove_file("#{base_name}.tar.gz", backup_file)
        if archive_file_name
          LOGGER.debug "Database archive file #{archive_file_name} created."
          return archive_file_name
        end
      end
    else
      LOGGER.error "No database config found for #{project_name}."
    end

    nil
  end

  # Check connection settings
  #
  # @return [Bool] is it possible to establish connection?
  def check_server_requirements
    result = false
    host = system_config('server', 'host')
    user = system_config('server', 'user')

    if user and host
      begin
        connection = Net::SSH.start(host, user)
        LOGGER.info "Connection with server #{user}@#{host} established."

        remote_install = connection.exec!("gem list -i #{APP_NAME}")
        if remote_install.to_s.strip == 'true'
          LOGGER.debug "#{APP_NAME} installed on remote server."
          result = true
        else
          LOGGER.error "#{APP_NAME} is not installed on remote server: `#{remote_install.strip}`."
        end
      rescue Exception => error
        LOGGER.error "Could not establish connection: #{error.message}"
          result = false
      ensure
        connection.close if !connection.nil? and !connection.closed?
      end
    else
      LOGGER.error 'Server user or host (or both of them) are not defined.'
    end

    result
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
      if execute(command)
        if File.exist?(backup_file_name)
          LOGGER.debug "Database backup file #{backup_file_name} created."
          file = File.open(backup_file_name, 'r')
          database_file_valid?(file) ? file : nil
        else
          LOGGER.error "Can't create database backup file `#{backup_file_name}`."
        end
      end
    else
      LOGGER.error 'Database container name is missing. Can\'t backup.'
    end
  end

  # Check basic content of SQL backup file
  #
  # @param file [File]
  #
  # @return [Bool]
  def database_file_valid?(file)
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

  # Move database backup to server
  #
  # @return [String, nil] path to backup on remote server
  def place_database_backup(file_path)
    result = nil
    destination_directory = '/tmp/'
    scp_command = "scp #{file_path} #{system_config('server', 'user')}@#{system_config('server', 'host')}:#{destination_directory}"
    if execute(scp_command)
      LOGGER.debug "Backup #{file_path} placed remotely to #{destination_directory}."

      FileUtils.rm(file_path)
      LOGGER.debug "Local file #{file_path} removed."

      result = destination_directory + File.basename(file_path)
    else
      LOGGER.error "Could not move #{file_path} to server."
    end
    result
  end

  # Execute command on remote server for processing database backup
  #
  # @param project_name [String]
  # @param remote_file_path [String]
  # @param sha256 [String, nil]
  #
  # @return [Bool] is operation success?
  def process_remote_database_backup(project_name, remote_file_path, sha256 = nil)
    result = false
    command = "#{APP_NAME} store_database_backup"
    command += " --project_name=#{project_name}"
    command += " --file=#{remote_file_path}"
    command += " --sha256=#{sha256}" unless sha256.nil?

    execute_remotely { result = (@remote_server_connection.exec!(command).exitstatus == 0) }

    result
  end

  # Create TAR GZ single file archive
  #
  # @param file_name [String] file name for new archive (including extension)
  # @param file [String, nil] target file name to archive
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

    final_file_name = "#{File.expand_path(File.dirname(file.path))}/#{file_name}"
    Zlib::GzipWriter.open(final_file_name) do |gz|
      gz.mtime = File.mtime(target.path)
      gz.orig_name = final_file_name
      gz.write IO.binread(target.path)
    end

    if File.exist?(file_name)
      file_name
    else
      nil
    end
  ensure
    target.close if target and !target.closed?
    nil
  end

  # Create TAR GZ archive and delete original file
  # @see #archive_file for arguments description
  def archive_and_remove_file(file_name, file)
    archive_name = archive_file(file_name, file)
    begin
      File.delete(file)
      # LOGGER.log "File #{file.path} was deleted."
      archive_name
    rescue StandardError => error
      LOGGER.warn "Can't delete file #{file.path} with error: #{error}."
      nil
    end
  end

  def remote_server_connect
    if check_server_requirements
      begin
        host = system_config('server', 'host')
        user = system_config('server', 'user')

        @remote_server_connection = Net::SSH.start(host, user)
      rescue Exception => error
        LOGGER.error "Could not establish connection: #{error.message}"
      end
    end
  end

  def remote_server_close_connection
    @remote_server_connection.close if !@remote_server_connection.nil? and !@remote_server_connection.closed?
  end

  def execute_remotely
    remote_server_connect
    yield if block_given?
    remote_server_close_connection
  end
end
