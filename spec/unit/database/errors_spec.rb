# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sxn::Database error classes" do
  describe Sxn::Database::Error do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("test error")
      expect(error.message).to eq("test error")
    end

    it "can be raised and caught" do
      expect { raise described_class, "test error" }.to raise_error(described_class, "test error")
    end
  end

  describe Sxn::Database::DuplicateSessionError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("duplicate session")
      expect(error.message).to eq("duplicate session")
    end

    it "can be raised and caught" do
      expect { raise described_class, "duplicate session" }.to raise_error(described_class, "duplicate session")
    end
  end

  describe Sxn::Database::SessionNotFoundError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("session not found")
      expect(error.message).to eq("session not found")
    end

    it "can be raised and caught" do
      expect { raise described_class, "session not found" }.to raise_error(described_class, "session not found")
    end
  end

  describe Sxn::Database::ConflictError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("conflict occurred")
      expect(error.message).to eq("conflict occurred")
    end

    it "can be raised and caught" do
      expect { raise described_class, "conflict occurred" }.to raise_error(described_class, "conflict occurred")
    end
  end

  describe Sxn::Database::MigrationError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("migration failed")
      expect(error.message).to eq("migration failed")
    end

    it "can be raised and caught" do
      expect { raise described_class, "migration failed" }.to raise_error(described_class, "migration failed")
    end
  end

  describe Sxn::Database::IntegrityError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("integrity violation")
      expect(error.message).to eq("integrity violation")
    end

    it "can be raised and caught" do
      expect { raise described_class, "integrity violation" }.to raise_error(described_class, "integrity violation")
    end
  end

  describe Sxn::Database::ConnectionError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("connection failed")
      expect(error.message).to eq("connection failed")
    end

    it "can be raised and caught" do
      expect { raise described_class, "connection failed" }.to raise_error(described_class, "connection failed")
    end
  end

  describe Sxn::Database::TransactionError do
    it "inherits from Sxn::Database::Error" do
      expect(described_class).to be < Sxn::Database::Error
    end

    it "can be instantiated with a message" do
      error = described_class.new("transaction failed")
      expect(error.message).to eq("transaction failed")
    end

    it "can be raised and caught" do
      expect { raise described_class, "transaction failed" }.to raise_error(described_class, "transaction failed")
    end
  end

  describe "error hierarchy" do
    it "all database errors inherit from Sxn::Database::Error" do
      database_error_classes = [
        Sxn::Database::DuplicateSessionError,
        Sxn::Database::SessionNotFoundError,
        Sxn::Database::ConflictError,
        Sxn::Database::MigrationError,
        Sxn::Database::IntegrityError,
        Sxn::Database::ConnectionError,
        Sxn::Database::TransactionError
      ]

      database_error_classes.each do |error_class|
        expect(error_class).to be < Sxn::Database::Error
      end
    end

    it "all database errors ultimately inherit from Sxn::Error" do
      database_error_classes = [
        Sxn::Database::Error,
        Sxn::Database::DuplicateSessionError,
        Sxn::Database::SessionNotFoundError,
        Sxn::Database::ConflictError,
        Sxn::Database::MigrationError,
        Sxn::Database::IntegrityError,
        Sxn::Database::ConnectionError,
        Sxn::Database::TransactionError
      ]

      database_error_classes.each do |error_class|
        expect(error_class).to be < Sxn::Error
      end
    end
  end

  describe "error scenarios" do
    it "can differentiate between different error types when caught" do
      errors_caught = []

      begin
        raise Sxn::Database::DuplicateSessionError, "duplicate"
      rescue Sxn::Database::Error => e
        errors_caught << e.class
      end

      begin
        raise Sxn::Database::SessionNotFoundError, "not found"
      rescue Sxn::Database::Error => e
        errors_caught << e.class
      end

      expect(errors_caught).to eq([
                                    Sxn::Database::DuplicateSessionError,
                                    Sxn::Database::SessionNotFoundError
                                  ])
    end

    it "can catch all database errors with base Database::Error" do
      database_error_classes = [
        Sxn::Database::DuplicateSessionError,
        Sxn::Database::SessionNotFoundError,
        Sxn::Database::ConflictError,
        Sxn::Database::MigrationError,
        Sxn::Database::IntegrityError,
        Sxn::Database::ConnectionError,
        Sxn::Database::TransactionError
      ]

      database_error_classes.each do |error_class|
        expect do
          raise error_class, "test"
        rescue Sxn::Database::Error
          # Should catch successfully
        end.not_to raise_error
      end
    end
  end
end
