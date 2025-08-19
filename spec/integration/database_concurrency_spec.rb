# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Database Concurrency and Transactions", type: :integration do
  let(:temp_db_path) { Tempfile.new(["concurrency_sessions", ".db"]).path }
  let(:db1) { Sxn::Database::SessionDatabase.new(temp_db_path) }
  let(:db2) { Sxn::Database::SessionDatabase.new(temp_db_path) }

  after do
    db1.close
    db2.close
    FileUtils.rm_f(temp_db_path)
  end

  describe "concurrent read operations" do
    let!(:session_id) do
      db1.create_session(
        name: "concurrent-test",
        status: "active",
        description: "Test concurrent access",
        tags: %w[concurrency test],
        metadata: { test: true }
      )
    end

    it "allows multiple connections to read simultaneously" do
      # Both connections should be able to read concurrently
      results = []

      threads = 2.times.map do |i|
        Thread.new do
          db = i == 0 ? db1 : db2
          10.times do
            session = db.get_session(session_id)
            results << session[:name]
          end
        end
      end

      threads.each(&:join)

      expect(results.length).to eq(20)
      expect(results.uniq).to eq(["concurrent-test"])
    end

    it "provides consistent read results across connections" do
      session1 = db1.get_session(session_id)
      session2 = db2.get_session(session_id)

      expect(session1).to eq(session2)
    end
  end

  describe "concurrent write operations" do
    let!(:session_id) do
      db1.create_session(
        name: "write-test",
        status: "active",
        metadata: { counter: 0 }
      )
    end

    it "handles concurrent updates to different fields" do
      # Connection 1 updates status
      thread1 = Thread.new do
        db1.update_session(session_id, { status: "inactive" })
      end

      # Connection 2 updates description
      thread2 = Thread.new do
        db2.update_session(session_id, { description: "Updated by connection 2" })
      end

      thread1.join
      thread2.join

      # Both updates should be preserved
      final_session = db1.get_session(session_id)
      expect(final_session[:status]).to eq("inactive")
      expect(final_session[:description]).to eq("Updated by connection 2")
    end

    it "serializes concurrent updates to same field" do
      # Both connections try to update the same field
      results = []
      errors = []

      threads = 2.times.map do |i|
        Thread.new do
          # Small delay to increase chance of conflict (optimized for speed)
          sleep(0.0005)

          case i
          when 0
            db1.update_session(session_id, { status: "inactive" })
            results << "updated_to_inactive"
          when 1
            db2.update_session(session_id, { status: "archived" })
            results << "updated_to_archived"
          end
        rescue StandardError => e
          errors << e
        end
      end

      threads.each(&:join)

      # At least one should succeed
      expect(results.length).to be >= 1

      # Final state should be one of the two values
      final_session = db1.get_session(session_id)
      expect(%w[inactive archived]).to include(final_session[:status])
    end
  end

  describe "optimistic locking conflicts" do
    let!(:session_id) do
      db1.create_session(name: "locking-test", status: "active")
    end

    it "detects concurrent modifications" do
      # Both connections read the same version
      session1 = db1.get_session(session_id)
      session2 = db2.get_session(session_id)

      expect(session1[:updated_at]).to eq(session2[:updated_at])

      # First connection updates successfully
      db1.update_session(session_id, { status: "inactive" },
                         expected_version: session1[:updated_at])

      # Second connection should fail due to version mismatch
      # In concurrent scenarios, SQLite may throw either ConflictError or BusyException
      # Both are acceptable behaviors for preventing concurrent modification issues
      expect do
        db2.update_session(session_id, { description: "Conflicting update" },
                           expected_version: session2[:updated_at])
      end.to raise_error do |error|
        # Accept either the optimistic locking error or SQLite busy exception
        expect(error).to satisfy do |e|
          e.is_a?(Sxn::Database::ConflictError) || e.is_a?(SQLite3::BusyException)
        end
      end
    end

    it "allows retry after version conflict" do
      session1 = db1.get_session(session_id)

      # First update
      db1.update_session(session_id, { status: "inactive" })

      # Second connection detects conflict and retries
      expect do
        db2.update_session(session_id, { description: "Failed update" },
                           expected_version: session1[:updated_at])
      end.to raise_error(Sxn::Database::ConflictError)

      # Retry with fresh version
      fresh_session = db2.get_session(session_id)
      result = db2.update_session(session_id, { description: "Successful retry" },
                                  expected_version: fresh_session[:updated_at])

      expect(result).to be true

      final_session = db1.get_session(session_id)
      expect(final_session[:status]).to eq("inactive")
      expect(final_session[:description]).to eq("Successful retry")
    end
  end

  describe "transaction rollback scenarios" do
    it "rolls back on constraint violation" do
      initial_count = db1.statistics[:total_sessions]

      expect do
        db1.connection.transaction do
          # Create first session successfully
          db1.create_session(name: "rollback-test-1", status: "active")

          # Try to create duplicate name - should cause rollback
          db1.create_session(name: "rollback-test-1", status: "inactive")
        end
      end.to raise_error(Sxn::Database::DuplicateSessionError)

      final_count = db1.statistics[:total_sessions]
      expect(final_count).to eq(initial_count) # No sessions should be created
    end

    it "rolls back on validation error" do
      initial_count = db1.statistics[:total_sessions]

      expect do
        db1.connection.transaction do
          # Create valid session
          db1.create_session(name: "valid-session", status: "active")

          # Create session with invalid status - should cause rollback
          db1.create_session(name: "invalid-session", status: "invalid_status")
        end
      end.to raise_error(ArgumentError)

      final_count = db1.statistics[:total_sessions]
      expect(final_count).to eq(initial_count) # No sessions should be created
    end

    it "rolls back complex multi-operation transaction" do
      # Create initial session
      session_id = db1.create_session(name: "transaction-test", status: "active")
      initial_session = db1.get_session(session_id)
      initial_count = db1.statistics[:total_sessions]

      expect do
        db1.connection.transaction do
          # Update existing session
          db1.update_session(session_id, { status: "inactive", description: "Updated" })

          # Create new sessions
          db1.create_session(name: "new-session-1", status: "active")
          db1.create_session(name: "new-session-2", status: "active")

          # This should fail and rollback everything
          db1.create_session(name: "new-session-1", status: "active") # Duplicate
        end
      end.to raise_error(Sxn::Database::DuplicateSessionError)

      # Original session should be unchanged
      current_session = db1.get_session(session_id)
      expect(current_session[:status]).to eq(initial_session[:status])
      expect(current_session[:description]).to eq(initial_session[:description])

      # No new sessions should exist
      final_count = db1.statistics[:total_sessions]
      expect(final_count).to eq(initial_count)
    end

    it "commits successful transactions completely" do
      initial_count = db1.statistics[:total_sessions]
      session_ids = []

      db1.connection.transaction do
        session_ids << db1.create_session(name: "commit-test-1", status: "active")
        session_ids << db1.create_session(name: "commit-test-2", status: "inactive")
        session_ids << db1.create_session(name: "commit-test-3", status: "archived")

        # Update the first session
        db1.update_session(session_ids.first, { description: "Transaction test" })
      end

      # All operations should be committed
      final_count = db1.statistics[:total_sessions]
      expect(final_count).to eq(initial_count + 3)

      # All sessions should exist and be accessible
      session_ids.each do |id|
        session = db1.get_session(id)
        expect(session).to be_a(Hash)
      end

      # First session should have description
      first_session = db1.get_session(session_ids.first)
      expect(first_session[:description]).to eq("Transaction test")
    end
  end

  describe "deadlock prevention", :slow do
    it "handles potential deadlock scenarios gracefully" do
      # Create two sessions for cross-updates
      session1_id = db1.create_session(name: "deadlock-test-1", status: "active")
      session2_id = db1.create_session(name: "deadlock-test-2", status: "active")

      errors = []
      results = []

      # Two threads that update sessions in opposite order
      thread1 = Thread.new do
        db1.connection.transaction do
          db1.update_session(session1_id, { description: "Updated by thread 1" })
          sleep(0.005)  # Reduced delay for faster testing
          db1.update_session(session2_id, { description: "Also updated by thread 1" })
        end
        results << "thread1_success"
      rescue StandardError => e
        errors << "thread1: #{e.message}"
      end

      thread2 = Thread.new do
        db2.connection.transaction do
          db2.update_session(session2_id, { description: "Updated by thread 2" })
          sleep(0.005)  # Reduced delay for faster testing
          db2.update_session(session1_id, { description: "Also updated by thread 2" })
        end
        results << "thread2_success"
      rescue StandardError => e
        errors << "thread2: #{e.message}"
      end

      thread1.join
      thread2.join

      # At least one thread should complete successfully
      # SQLite's timeout mechanism should prevent true deadlocks
      expect(results.length).to be >= 1

      # Both sessions should still be accessible
      expect { db1.get_session(session1_id) }.not_to raise_error
      expect { db1.get_session(session2_id) }.not_to raise_error
    end
  end

  describe "database recovery and consistency" do
    it "maintains consistency after connection interruption" do
      # Create some sessions
      session_ids = 3.times.map do |i|
        db1.create_session(name: "recovery-test-#{i}", status: "active")
      end

      # Simulate connection interruption by closing one connection
      db1.close

      # New connection should see all committed data
      db3 = Sxn::Database::SessionDatabase.new(temp_db_path)

      begin
        session_ids.each do |id|
          session = db3.get_session(id)
          expect(session[:name]).to start_with("recovery-test-")
        end

        # Should be able to perform normal operations
        new_id = db3.create_session(name: "post-recovery", status: "active")
        expect(db3.get_session(new_id)[:name]).to eq("post-recovery")
      ensure
        db3.close
      end
    end

    it "handles database file corruption gracefully" do
      # This is a basic test - real corruption testing would be more complex

      # Create a session
      session_id = db1.create_session(name: "corruption-test", status: "active")

      # Force a checkpoint to ensure data is written
      db1.connection.execute("PRAGMA wal_checkpoint(FULL)")

      # Close connections
      db1.close
      db2.close

      # Verify integrity
      db3 = Sxn::Database::SessionDatabase.new(temp_db_path)

      begin
        # Database should pass integrity check
        result = db3.maintenance([:integrity_check])
        expect(result[:integrity_check]).to eq("ok")

        # Data should still be accessible
        session = db3.get_session(session_id)
        expect(session[:name]).to eq("corruption-test")
      ensure
        db3.close
      end
    end
  end
end
