# frozen_string_literal: true

module Sxn
  module Templates
    module Errors
      # Base class for template-related errors
      class TemplateError < Sxn::Error; end

      # Raised when template syntax is invalid
      class TemplateSyntaxError < TemplateError; end

      # Raised when template processing fails
      class TemplateProcessingError < TemplateError; end

      # Raised when template file is not found
      class TemplateNotFoundError < TemplateError; end

      # Raised when template exceeds size limits
      class TemplateTooLargeError < TemplateError; end

      # Raised when template processing times out
      class TemplateTimeoutError < TemplateError; end

      # Raised when template contains security violations
      class TemplateSecurityError < TemplateError; end

      # Raised when template rendering encounters errors
      class TemplateRenderError < TemplateError; end

      # Raised when template variable collection fails
      class TemplateVariableError < TemplateError; end
    end
  end
end