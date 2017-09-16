require 'net/ssh'
require 'open3'
require 'logger'
require 'fileutils'
require 'digest'

LOGGER = Logger.new(STDOUT)
APP_NAME = 'backup_minister'

class BackupMinister
  @projects = nil
  @config_file_name = nil

  def initialize(file_name = nil)
    @config_file_name = file_name || CONFIG_FILE_NAME
    @config = check_config_file_exists
  end

  def system_config(*path)
    path.unshift 'settings'
    @config.dig(*path)
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

  # Check if backup_minister is installed
  #
  # @return [Bool]
  def backup_minister_installed?
    software_installed?(APP_NAME)
  end

  # Check if software is installed
  #
  # @return [Bool]
  def software_installed?(name)
    result = execute_with_result('type', name)
    result and /\A(#{name})(.)+(#{name})$/.match(result).to_a.count >= 3
  end

  # Wrapper for `system` with check
  #
  # @return [Bool] true if exit status is 0
  def execute(command)
    system command
    code = $?.exitstatus
    if code > 0
      LOGGER.warn "Failed to execute command `#{command}` with code #{code}."
      false
    else
      true
    end
  end

  # @return [Bool]
  def create_nested_directory(path)
    result = false

    begin
      FileUtils::mkdir_p(path)
      LOGGER.debug "Directory `#{path}` created."
      result = true
    rescue Error => error
      LOGGER.error "Can't create directory `#{path}` with error #{error.message}."
    end

    result
  end

  def execute_with_result(command, arguments = [])
    out, st = Open3.capture2(command, arguments)
    LOGGER.warn "Failed to execute command `#{command}` with code #{st.exitstatus}." unless st.success?
    out
  end

  # Get SHA256 Hash of file
  #
  # @param file_path [String] path to file
  #
  # @return [String, nil]
  def file_sha256_hash(file_path)
    file = File.read(file_path)
    Digest::SHA256.hexdigest(file) if file
  end

  private

  attr_accessor :config

  def check_config_file_exists
    if File.exists?(@config_file_name)
      YAML.load File.read(@config_file_name)
    else
      raise RuntimeError, "No config file #{@config_file_name} found"
    end
  end
end

require 'backup_minister/agent'
require 'backup_minister/server'

# Extensions
require 'backup_minister/core/string'