# frozen_string_literal: true

module Sxn
  # Runtime validation helpers for Thor commands and type safety
  module RuntimeValidations
    class << self
      # Validate Thor command arguments at runtime
      def validate_thor_arguments(command_name, args, options, validations)
        # Validate argument count
        if validations[:args]
          count_range = validations[:args][:count]
          raise ArgumentError, "#{command_name} expects #{count_range} arguments, got #{args.size}" if count_range && !count_range.include?(args.size)

          # Validate argument types
          if validations[:args][:types]
            args.each_with_index do |arg, index|
              expected_types = Array(validations[:args][:types][index] || validations[:args][:types].last)
              unless expected_types.any? { |type| arg.is_a?(type) }
                raise TypeError, "#{command_name} argument #{index + 1} must be #{expected_types.join(" or ")}"
              end
            end
          end
        end

        # Validate options
        if validations[:options]
          options.each do |key, value|
            validate_option_type(command_name, key, value, validations[:options][key.to_sym]) if validations[:options][key.to_sym]
          end
        end

        true
      end

      # Validate and coerce types for runtime safety
      def validate_and_coerce_type(value, target_type, context = nil)
        case target_type.name
        when "String"
          value.to_s
        when "Integer"
          Integer(value)
        when "Float"
          Float(value)
        when "TrueClass", "FalseClass", "Boolean"
          !!value
        when "Array"
          Array(value)
        when "Hash"
          value.is_a?(Hash) ? value : {}
        else
          value
        end
      rescue StandardError => e
        raise TypeError, "Cannot coerce #{value.class} to #{target_type} in #{context}: #{e.message}"
      end

      # Validate template variables for Liquid templates
      def validate_template_variables(variables)
        return {} unless variables.is_a?(Hash)

        # Ensure all required variable categories exist
        validated = {
          session: variables[:session] || {},
          project: variables[:project] || {},
          git: variables[:git] || {},
          user: variables[:user] || {},
          environment: variables[:environment] || {},
          timestamp: variables[:timestamp] || {},
          custom: variables[:custom] || {}
        }

        # Ensure no nil values in the hash
        validated.each do |key, value|
          validated[key] = {} unless value.is_a?(Hash)
        end

        validated
      end

      private

      def validate_option_type(command_name, key, value, expected_type)
        case expected_type
        when :boolean
          raise TypeError, "#{command_name} option --#{key} must be boolean" unless [true, false, nil].include?(value)
        when :string
          raise TypeError, "#{command_name} option --#{key} must be a string" unless value.nil? || value.is_a?(String)
        when :integer
          raise TypeError, "#{command_name} option --#{key} must be an integer" unless value.nil? || value.is_a?(Integer)
        when :array
          raise TypeError, "#{command_name} option --#{key} must be an array" unless value.nil? || value.is_a?(Array)
        end
      end
    end
  end
end
