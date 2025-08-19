# frozen_string_literal: true

require_relative "database/errors"
require_relative "database/session_database"

module Sxn
  # Database layer for session storage and management
  #
  # This module provides SQLite-based storage for session metadata,
  # replacing filesystem scanning with O(1) indexed lookups.
  #
  # Features:
  # - High-performance SQLite with optimized indexes
  # - ACID transactions with rollback support
  # - Full-text search capabilities
  # - JSON metadata storage
  # - Connection pooling and concurrent access handling
  # - Automatic schema migrations
  #
  # This module follows Ruby gem best practices by using explicit requires
  # instead of autoload for better loading performance and dependency clarity.
  module Database
  end
end
