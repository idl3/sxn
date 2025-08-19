# frozen_string_literal: true

require_relative "security/secure_path_validator"
require_relative "security/secure_command_executor"
require_relative "security/secure_file_copier"

module Sxn
  # Security namespace provides components for secure file operations,
  # command execution, path validation, and audit logging.
  #
  # This module follows Ruby gem best practices by using explicit requires
  # instead of autoload for better loading performance and dependency clarity.
  module Security
  end
end