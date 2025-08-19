# typed: true

target :lib do
  signature "sig"
  
  check "lib"
  
  # Core library files
  library "pathname"
  library "logger"
  library "json"
  library "yaml"
  library "fileutils"
  library "tempfile"
  library "digest"
  library "time"
  library "optparse"
  library "English"
  library "shellwords"
  library "open3"
  library "stringio"
  library "monitor"
  library "mutex_m"
  
  # Gem dependencies
  library "thor"
  library "tty-prompt"
  library "tty-table"
  library "tty-progressbar"
  library "pastel"
  library "liquid"
  
  # Configure Steep options
  configure_code_diagnostics do |hash|
    # Allow some flexibility while we improve type coverage
    hash[Steep::Diagnostic::Ruby::NoMethod] = :warning
    hash[Steep::Diagnostic::Ruby::UnresolvedOverloading] = :hint
    hash[Steep::Diagnostic::Ruby::MethodDefinitionMissing] = :hint
    hash[Steep::Diagnostic::Ruby::IncompatibleAssignment] = :warning
  end
end

target :spec do
  signature "sig"
  
  check "spec"
  
  library "rspec"
  library "faker"
  library "climate_control"
  library "webmock"
  
  # Inherit libraries from :lib target
  library "pathname"
  library "logger"
  library "json"
  library "yaml"
  library "fileutils"
  
  configure_code_diagnostics do |hash|
    # Be more lenient with test code
    hash[Steep::Diagnostic::Ruby::NoMethod] = :hint
    hash[Steep::Diagnostic::Ruby::UnresolvedOverloading] = nil
    hash[Steep::Diagnostic::Ruby::MethodDefinitionMissing] = nil
  end
end