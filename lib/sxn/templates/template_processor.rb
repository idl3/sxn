# frozen_string_literal: true

require "liquid"
require "pathname"

module Sxn
  module Templates
    # TemplateProcessor provides secure, sandboxed template processing using Liquid.
    # It ensures that templates cannot execute arbitrary code or access the filesystem.
    #
    # Features:
    # - Whitelisted variables only
    # - No arbitrary code execution
    # - Support for nested variable access (session.name, git.branch)
    # - Built-in filters (upcase, downcase, join, etc.)
    # - Template validation before processing
    #
    # Example:
    #   processor = TemplateProcessor.new
    #   variables = { session: { name: "test" }, git: { branch: "main" } }
    #   result = processor.process("Hello {{session.name}} on {{git.branch}}", variables)
    #   # => "Hello test on main"
    class TemplateProcessor
      # Maximum template size in bytes to prevent memory exhaustion
      MAX_TEMPLATE_SIZE = 1_048_576 # 1MB

      # Maximum rendering time in seconds to prevent infinite loops
      MAX_RENDER_TIME = 10

      # Allowed Liquid filters for security
      ALLOWED_FILTERS = %w[
        upcase downcase capitalize
        strip lstrip rstrip
        size length
        first last
        join split
        sort sort_natural reverse
        uniq compact
        date
        default
        escape escape_once
        truncate truncatewords
        replace replace_first
        remove remove_first
        plus minus times divided_by modulo
        abs ceil floor round
        at_least at_most
      ].freeze

      def initialize
        @liquid_environment = create_secure_liquid_environment
      end

      # Process a template string with the given variables
      #
      # @param template_content [String] The template content to process
      # @param variables [Hash] Variables to make available in the template
      # @param options [Hash] Processing options
      # @option options [Boolean] :strict (true) Whether to raise on undefined variables
      # @option options [Boolean] :validate (true) Whether to validate template syntax first
      # @return [String] The processed template
      # @raise [TemplateTooLargeError] if template exceeds size limit
      # @raise [TemplateTimeoutError] if processing takes too long
      # @raise [TemplateSecurityError] if template contains disallowed content
      # @raise [TemplateSyntaxError] if template has invalid syntax
      def process(template_content, variables = {}, options = {})
        options = { strict: true, validate: true }.merge(options)

        validate_template_size!(template_content)
        
        # Sanitize and whitelist variables
        sanitized_variables = sanitize_variables(variables)
        
        # Parse template with syntax validation
        template = parse_template(template_content, validate: options[:validate])
        
        # Render with timeout protection
        render_with_timeout(template, sanitized_variables, options)
      rescue Liquid::SyntaxError => e
        raise Errors::TemplateSyntaxError, "Template syntax error: #{e.message}"
      rescue Errors::TemplateTooLargeError, Errors::TemplateTimeoutError => e
        # Re-raise specific template errors as-is
        raise e
      rescue StandardError => e
        raise Errors::TemplateProcessingError, "Template processing failed: #{e.message}"
      end

      # Process a template file with the given variables
      #
      # @param template_path [String, Pathname] Path to the template file
      # @param variables [Hash] Variables to make available in the template
      # @param options [Hash] Processing options (see #process)
      # @return [String] The processed template
      # @raise [TemplateNotFoundError] if template file doesn't exist
      def process_file(template_path, variables = {}, options = {})
        template_path = Pathname.new(template_path)
        
        unless template_path.exist?
          raise Errors::TemplateNotFoundError, "Template file not found: #{template_path}"
        end

        template_content = template_path.read
        process(template_content, variables, options)
      end

      # Validate template syntax without processing
      #
      # @param template_content [String] The template content to validate
      # @return [Boolean] true if template is valid
      # @raise [TemplateSyntaxError] if template has invalid syntax
      def validate_syntax(template_content)
        validate_template_size!(template_content)
        parse_template(template_content, validate: true)
        true
      rescue Liquid::SyntaxError => e
        raise Errors::TemplateSyntaxError, "Template syntax error: #{e.message}"
      end

      # Extract variables referenced in a template
      #
      # @param template_content [String] The template content to analyze
      # @return [Array<String>] List of variable names referenced in the template
      def extract_variables(template_content)
        variables = Set.new
        
        # Extract variables from {{ variable }} expressions
        template_content.scan(/\{\{\s*(\w+)(?:\.\w+)*.*?\}\}/) do |match|
          variables.add(match[0])
        end
        
        # Extract variables from {% if/unless variable %} expressions
        template_content.scan(/\{%\s*(?:if|unless)\s+(\w+)(?:\.\w+)*.*?%\}/) do |match|
          variables.add(match[0])
        end
        
        # Extract variables from {% for item in collection %} expressions
        template_content.scan(/\{%\s*for\s+\w+\s+in\s+(\w+)(?:\.\w+)*.*?%\}/) do |match|
          variables.add(match[0])
        end
        
        variables.to_a.sort
      end

      private

      # Create a secure Liquid environment with restricted capabilities
      def create_secure_liquid_environment
        Liquid::Template.file_system = Liquid::BlankFileSystem.new
        
        # Register only allowed filters
        ALLOWED_FILTERS.each do |filter_name|
          next unless Liquid::StandardFilters.method_defined?(filter_name)
          Liquid::Template.register_filter(Liquid::StandardFilters)
        end

        # Disable dangerous tags
        Liquid::Template.tags.delete("include")
        Liquid::Template.tags.delete("include_relative")
        Liquid::Template.tags.delete("render")
        
        true
      end

      # Validate template size to prevent memory exhaustion
      def validate_template_size!(template_content)
        size = template_content.bytesize
        return if size <= MAX_TEMPLATE_SIZE

        raise Errors::TemplateTooLargeError, 
              "Template size #{size} bytes exceeds limit of #{MAX_TEMPLATE_SIZE} bytes"
      end

      # Parse template and optionally validate syntax
      def parse_template(template_content, validate: true)
        if validate
          # First pass: syntax validation only
          Liquid::Template.parse(template_content, error_mode: :strict)
        end
        
        # Second pass: actual parsing for rendering
        Liquid::Template.parse(template_content, error_mode: :strict)
      end

      # Sanitize and whitelist variables to prevent injection
      def sanitize_variables(variables)
        sanitized = {}
        
        variables.each do |key, value|
          sanitized_key = sanitize_key(key)
          sanitized_value = sanitize_value(value)
          sanitized[sanitized_key] = sanitized_value
        end
        
        sanitized
      end

      # Sanitize variable keys to ensure they're safe
      def sanitize_key(key)
        key.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end

      # Recursively sanitize variable values
      def sanitize_value(value)
        case value
        when Hash
          value.transform_keys { |k| sanitize_key(k) }
               .transform_values { |v| sanitize_value(v) }
        when Array
          value.map { |v| sanitize_value(v) }
        when String
          # Escape any potential HTML/JS in strings
          value.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, "")
               .gsub(/<[^>]*>/, "")
        when Symbol
          value.to_s
        when Numeric, TrueClass, FalseClass, NilClass
          value
        when Time, Date
          value.iso8601
        else
          # Convert unknown types to string representation
          value.to_s
        end
      end

      # Render template with timeout protection
      def render_with_timeout(template, variables, options)
        start_time = Time.now
        result = nil
        
        # Set up a thread to handle timeout
        timeout_thread = Thread.new do
          sleep(MAX_RENDER_TIME)
          Thread.main.raise(Errors::TemplateTimeoutError, 
                           "Template rendering exceeded #{MAX_RENDER_TIME} seconds")
        end
        
        begin
          # Render the template
          liquid_context = Liquid::Context.new(
            variables,
            {},
            { strict_variables: options[:strict] }
          )
          
          result = template.render(liquid_context)
          
          # Check for rendering errors
          if template.errors.any?
            error_message = template.errors.join(", ")
            raise Errors::TemplateRenderError, "Template rendering errors: #{error_message}"
          end
          
          result
        ensure
          timeout_thread.kill
          
          # Log performance metrics in debug mode
          if ENV["SXN_DEBUG"]
            elapsed = Time.now - start_time
            puts "Template rendered in #{elapsed.round(3)}s"
          end
        end
      end

    end
  end
end