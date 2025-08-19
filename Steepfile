# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature "sig"
  
  check "lib"
  
  # Ignore non-Ruby files
  ignore "lib/sxn/templates/**/*.liquid"
  
  # Standard library types
  library "pathname", "logger", "json", "yaml", "fileutils", "optparse"
  library "tempfile", "digest", "time", "shellwords", "open3", "stringio"
  library "monitor", "mutex_m", "timeout", "forwardable"
  
  # Configure diagnostic settings
  configure_code_diagnostics do |hash|
    # Critical errors that must be fixed
    hash[D::Ruby::MethodArityMismatch] = :error
    hash[D::Ruby::RequiredBlockMissing] = :error
    hash[D::Ruby::InsufficientKeywordArguments] = :error
    hash[D::Ruby::InsufficientPositionalArguments] = :error
    hash[D::Ruby::ReturnTypeMismatch] = :error
    hash[D::Ruby::MethodBodyTypeMismatch] = :warning
    
    # Framework limitations and metaprogramming
    hash[D::Ruby::UnexpectedKeywordArgument] = :information  # Thor dynamic args
    hash[D::Ruby::UnexpectedPositionalArgument] = :information  # Thor dynamic args
    hash[D::Ruby::FallbackAny] = :hint  # Template variable resolution
    hash[D::Ruby::NoMethod] = :hint  # Dynamic method calls
    
    # RBS coverage gaps
    hash[D::Ruby::UnknownConstant] = :hint
    hash[D::Ruby::MethodDefinitionMissing] = :hint
    hash[D::Ruby::UndeclaredMethodDefinition] = :hint
    
    # Type coercion
    hash[D::Ruby::ArgumentTypeMismatch] = :information
    hash[D::Ruby::IncompatibleAssignment] = :warning
    hash[D::Ruby::MethodReturnTypeAnnotationMismatch] = :warning
    
    # Other warnings
    hash[D::Ruby::UnexpectedBlockGiven] = :warning
    hash[D::Ruby::UnresolvedOverloading] = :warning
    hash[D::Ruby::UnexpectedJump] = :hint
    hash[D::Ruby::UnannotatedEmptyCollection] = :hint
  end
end