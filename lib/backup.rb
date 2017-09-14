module Lib
    class Backup
        @projects = nil
        @config_file_name = nil

        def initialize(file_name = nil)
            @config_file_name = file_name || CONFIG_FILE_NAME
            @config = check_config_file_exists
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
end