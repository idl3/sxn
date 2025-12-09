# frozen_string_literal: true

require "yaml"

module Sxn
  module Core
    # Manages .sxnrc session configuration files
    class SessionConfig
      FILENAME = ".sxnrc"

      attr_reader :session_path, :config_path

      def initialize(session_path)
        @session_path = session_path
        @config_path = File.join(session_path, FILENAME)
      end

      def create(parent_sxn_path:, default_branch:, session_name:)
        config = {
          "version" => 1,
          "parent_sxn_path" => parent_sxn_path,
          "default_branch" => default_branch,
          "session_name" => session_name,
          "created_at" => Time.now.iso8601
        }
        File.write(@config_path, YAML.dump(config))
        config
      end

      def exists?
        File.exist?(@config_path)
      end

      def read
        return nil unless exists?

        YAML.safe_load_file(@config_path) || {}
      rescue Psych::SyntaxError
        nil
      end

      def parent_sxn_path
        read&.dig("parent_sxn_path")
      end

      def default_branch
        read&.dig("default_branch")
      end

      def session_name
        read&.dig("session_name")
      end

      def project_root
        parent_path = parent_sxn_path
        return nil unless parent_path

        # parent_sxn_path points to .sxn folder, project root is its parent
        File.dirname(parent_path)
      end

      def update(updates)
        config = read || {}
        updates.each do |key, value|
          config[key.to_s] = value
        end
        File.write(@config_path, YAML.dump(config))
        config
      end

      # Class method: Find .sxnrc by walking up directory tree
      def self.find_from_path(start_path)
        current = File.expand_path(start_path)

        while current != "/" && current != File.dirname(current)
          config_path = File.join(current, FILENAME)
          return new(current) if File.exist?(config_path)

          current = File.dirname(current)
        end

        nil
      end

      # Class method: Check if path is within a session
      def self.in_session?(path = Dir.pwd)
        !find_from_path(path).nil?
      end
    end
  end
end
