class BackupMinister::Server < BackupMinister

  # Is it possible to wright to target backups location?
  #
  # @return [Bool]
  def location_accessible?
    result = false

    location = system_config('server', 'location')
    if location.nil?
      LOGGER.error 'Location path is not set.'
    else
      if File.directory?(location)
        LOGGER.debug "Directory `#{location}` exists."
        result = true
      else
        LOGGER.debug "Directory `#{location}` doesn't exists. Will try to create it."
        result = create_nested_directory(location)
      end
    end

    result
  end

  # @param project_name [String]
  # @param backup_file_path [String]
  # @param project_config [Hash]
  def place_database_backup(project_name, backup_file_path, project_config = {})
    return false unless location_accessible?

    result = false
    project_location = project_location(project_name, project_config)
    result = place_file(backup_file_path, "#{project_location}/database") if project_location

    result
  end

  # Place file to directory
  #
  # @param file [String]
  # @param location [String]
  def place_file(file, location)
    result = false

    if File.exist?(file)
      if File.directory?(location) or create_nested_directory(location)
        begin
          FileUtils.move file, location
          LOGGER.debug "File #{file} moved to #{location}."
          result = true
        rescue Error => error
          LOGGER.warn "Can't move file with error: #{error.message}."
        end
      end
    else
      LOGGER.warn "No such file #{file}."
    end

    result
  end


  # Path to root project's directory
  #
  # @param project_name [String]
  # @param project_config [Hash]
  #
  # @return [String, nil]
  def project_location(project_name, project_config = {})
    result = nil

    project_dir = project_config['remote_project_location'] || project_name.underscore
    project_dir = /[^\/]([a-zA-Z0-9\-_])+([\/])?\z/.match(project_dir).to_a.first
    if project_dir
      project_full_path = system_config('server', 'location') + '/' + project_dir
      if File.directory?(project_full_path) or create_nested_directory(project_full_path)
        LOGGER.debug "Project location is #{project_full_path}."
        result = project_full_path
      end
    else
      LOGGER.error "Could not get project location for #{project_name}."
    end

    result
  end

  # Path to project directory for files
  #
  # @param project_name [String]
  # @param project_config [Hash]
  #
  # @return [String, nil]
  def project_files_location(project_name, project_config = {})
    result = nil

    project_dir = project_location(project_name, project_config)
    if project_dir
      files_path = '/files'
      full_files_path = project_dir + files_path
      result = full_files_path if File.directory?(full_files_path) or create_nested_directory(full_files_path)
    end

    result
  end
end
