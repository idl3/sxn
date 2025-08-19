# frozen_string_literal: true

module FileHelper
  def create_test_file(path, content = "test content")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def create_test_config(base_path, config = {})
    config_path = File.join(base_path, ".sxn", "config.yml")
    FileUtils.mkdir_p(File.dirname(config_path))

    default_config = {
      "version" => 1,
      "sessions_folder" => "sessions",
      "projects" => {}
    }

    File.write(config_path, default_config.merge(config).to_yaml)
    config_path
  end

  def create_sensitive_file(path, permissions = 0o600)
    create_test_file(path, "sensitive content")
    File.chmod(permissions, path)
    path
  end

  def within_temp_directory
    Dir.mktmpdir("sxn_test") do |dir|
      original_pwd = Dir.pwd
      Dir.chdir(dir)
      yield dir
    ensure
      Dir.chdir(original_pwd) if original_pwd
    end
  end
end
