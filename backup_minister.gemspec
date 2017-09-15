require 'rake'

Gem::Specification.new do |s|
  s.name                    = 'backup_minister'
  s.version                 = '0.0.1'
  s.date                    = '2017-09-14'
  s.summary                 = 'Backup Minister'
  s.description             = 'Provide tools for multi-server backups with docker support'
  s.authors                 = 'Ilya Krigouzov'
  s.email                   = 'webmaster@oniksfly.com'
  s.files                   = FileList['lib/*.rb', 'lib/backup_minister/*.rb', 'lib/backup_minister/core/*.rb']
  s.homepage                = 'https://github.com/oniksfly/backup-minister'
  s.executables             << 'backup_minister'
  s.license                 = 'Nonstandard'
  s.required_ruby_version   = '>= 2.0'
  s.add_runtime_dependency 'net-ssh', '~> 4.0'
  s.add_runtime_dependency 'thor', '~> 0.20'
end