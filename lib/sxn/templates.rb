# frozen_string_literal: true

# Sxn Templates module provides secure, sandboxed template processing
# using the Liquid template engine. It includes built-in templates for
# common project types and comprehensive security measures.
#
# Features:
# - Liquid-based template processing (safe, no code execution)
# - Whitelisted variables and filters
# - Built-in templates for Rails, JavaScript, and common projects
# - Template security validation
# - Variable collection from session, git, project, and environment
# - Performance optimizations with caching
#
# Example usage:
#   engine = Sxn::Templates::TemplateEngine.new(session: session, project: project)
#   engine.process_template("rails/CLAUDE.md", "/path/to/output.md")

require_relative "templates/errors"
require_relative "templates/template_security"
require_relative "templates/template_processor"
require_relative "templates/template_variables"
require_relative "templates/template_engine"

module Sxn
  module Templates
  end
end
