# frozen_string_literal: true

module Sxn
  module Database
    # Base error class for all database-related errors
    class Error < Sxn::Error; end

    # Raised when trying to create a session with a name that already exists
    class DuplicateSessionError < Error; end

    # Raised when trying to access a session that doesn't exist
    class SessionNotFoundError < Error; end

    # Raised when concurrent updates conflict (optimistic locking)
    class ConflictError < Error; end

    # Raised when database schema migration fails
    class MigrationError < Error; end

    # Raised when database integrity checks fail
    class IntegrityError < Error; end

    # Raised when database connection fails
    class ConnectionError < Error; end

    # Raised when transaction rollback occurs
    class TransactionError < Error; end
  end
end
