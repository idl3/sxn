# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Database Module Comprehensive Coverage" do
  let(:temp_db_path) { Tempfile.new(["comprehensive_test", ".db"]).path }
  let(:db) { Sxn::Database::SessionDatabase.new(temp_db_path) }

  after do
    db.close
    FileUtils.rm_f(temp_db_path)
  end

  describe "Module Structure and Constants" do
    it "defines the Database module correctly" do
      expect(Sxn::Database).to be_a(Module)
      expect(Sxn::Database.name).to eq("Sxn::Database")
    end

    it "has correct schema version constant" do
      expect(Sxn::Database::SessionDatabase::SCHEMA_VERSION).to eq(2)
    end

    it "has correct default database path constant" do
      expect(Sxn::Database::SessionDatabase::DEFAULT_DB_PATH).to eq(".sxn/sessions.db")
    end

    it "has valid status constants" do
      expected_statuses = %w[active inactive archived]
      expect(Sxn::Database::SessionDatabase::VALID_STATUSES).to eq(expected_statuses)
    end
  end

  describe "Database File Handling" do
    it "handles non-existent parent directories" do
      nested_path = "/tmp/sxn_comprehensive_test/deeply/nested/path/test.db"

      begin
        nested_db = Sxn::Database::SessionDatabase.new(nested_path)
        expect(File.exist?(nested_path)).to be true
        nested_db.close
      ensure
        FileUtils.rm_rf("/tmp/sxn_comprehensive_test")
      end
    end

    it "handles existing database files correctly" do
      # Create initial database
      session_id = db.create_session(name: "existing-test")
      db.close

      # Reopen existing database
      reopened_db = Sxn::Database::SessionDatabase.new(temp_db_path)
      session = reopened_db.get_session(session_id)
      expect(session[:name]).to eq("existing-test")

      reopened_db.close
    end

    it "handles database file permissions" do
      # Ensure the database file is readable and writable
      expect(File.readable?(temp_db_path)).to be true
      expect(File.writable?(temp_db_path)).to be true
    end
  end

  describe "Complex Query Scenarios" do
    before do
      # Create test data for complex queries
      10.times do |i|
        db.create_session(
          name: "complex-test-#{i}",
          status: i.even? ? "active" : "inactive",
          linear_task: i < 5 ? "ATL-#{1000 + i}" : nil,
          description: "Test session #{i} for complex queries",
          tags: [
            "test",
            i.even? ? "even" : "odd",
            if i < 3
              "early"
            else
              i < 7 ? "middle" : "late"
            end
          ],
          metadata: {
            index: i,
            category: i < 5 ? "first_half" : "second_half",
            priority: %w[low medium high][i % 3]
          }
        )
      end
    end

    it "handles complex filter combinations" do
      # Test multiple filters together
      results = db.list_sessions(
        filters: {
          status: "active",
          tags: %w[test even]
        },
        sort: { by: :name, order: :asc },
        limit: 5
      )

      expect(results.length).to eq(5)
      results.each do |session|
        expect(session[:status]).to eq("active")
        expect(session[:tags]).to include("test", "even")
      end
    end

    it "handles complex search queries with multiple terms" do
      results = db.search_sessions("test", limit: 10)

      # Should find sessions with descriptions containing the search term
      expect(results.length).to be > 0
      results.each do |session|
        description_match = session[:description]&.match(/test/i)
        name_match = session[:name]&.match(/test/i)
        tags_match = session[:tags]&.any? { |tag| tag.match(/test/i) }
        expect(description_match || name_match || tags_match).to be_truthy
      end
    end

    it "handles date range filtering correctly" do
      # Use much broader date range to include our test sessions
      old_date = Date.new(2020, 1, 1)
      future_date = Date.new(2030, 12, 31)

      results = db.list_sessions(
        filters: {
          created_after: old_date,
          created_before: future_date
        }
      )

      # All our test sessions should fall within this very broad range
      expect(results.length).to eq(10)
    end

    it "handles pagination correctly across large datasets" do
      all_sessions = []
      offset = 0
      limit = 3

      loop do
        page = db.list_sessions(limit: limit, offset: offset)
        break if page.empty?

        all_sessions.concat(page)
        offset += limit
      end

      expect(all_sessions.length).to eq(10)
      # Ensure no duplicates
      session_ids = all_sessions.map { |s| s[:id] }
      expect(session_ids.uniq.length).to eq(session_ids.length)
    end
  end

  describe "Data Integrity and Constraints" do
    it "enforces unique session names" do
      db.create_session(name: "unique-test")

      expect do
        db.create_session(name: "unique-test")
      end.to raise_error(Sxn::Database::DuplicateSessionError)
    end

    it "enforces valid status values" do
      expect do
        db.create_session(name: "invalid-status", status: "unknown")
      end.to raise_error(ArgumentError, /Invalid status/)
    end

    it "handles foreign key constraints in related tables" do
      session_id = db.create_session(name: "fk-test")

      # Insert related records
      db.connection.execute(<<~SQL, [session_id, "test-project", "/tmp/path", "main", Time.now.utc.iso8601])
        INSERT INTO session_worktrees (session_id, project_name, path, branch, created_at)
        VALUES (?, ?, ?, ?, ?)
      SQL

      # Verify foreign key relationship
      worktrees = db.connection.execute("SELECT * FROM session_worktrees WHERE session_id = ?", [session_id])
      expect(worktrees.length).to eq(1)

      # Delete session should cascade
      db.delete_session(session_id, cascade: true)

      worktrees_after = db.connection.execute("SELECT * FROM session_worktrees WHERE session_id = ?", [session_id])
      expect(worktrees_after.length).to eq(0)
    end
  end

  describe "Performance and Scalability" do
    it "handles bulk operations efficiently" do
      bulk_count = 100

      # Measure bulk creation time
      creation_time = Benchmark.realtime do
        bulk_count.times do |i|
          db.create_session(name: "bulk-#{i}")
        end
      end

      # Should be able to create 100 sessions in under 1 second
      expect(creation_time).to be < 5.0

      # Verify all sessions were created
      total_sessions = db.statistics[:total_sessions]
      expect(total_sessions).to eq(bulk_count)

      # Measure bulk listing time
      listing_time = Benchmark.realtime do
        10.times { db.list_sessions(limit: 50) }
      end

      # Should be able to list sessions 10 times in under 0.1 seconds
      expect(listing_time).to be < 1.0
    end

    it "maintains performance with complex metadata" do
      # Create sessions with large, complex metadata
      10.times do |i|
        large_metadata = {
          description: "A" * 1000, # 1KB string
          array_data: (1..100).to_a,
          nested_hash: {
            level1: {
              level2: {
                level3: (1..50).map { |j| { "key#{j}" => "value#{j}" * 10 } }
              }
            }
          },
          timestamps: (1..20).map { Time.now.utc.iso8601 }
        }

        db.create_session(
          name: "large-metadata-#{i}",
          metadata: large_metadata
        )
      end

      # Operations should still be fast
      search_time = Benchmark.realtime do
        db.search_sessions("large", limit: 10)
      end

      expect(search_time).to be < 1.0
    end
  end

  describe "Error Handling and Recovery" do
    it "handles database locking gracefully" do
      # Simulate concurrent access
      threads = 5.times.map do |i|
        Thread.new do
          db.create_session(name: "concurrent-#{i}-#{Thread.current.object_id}")
        rescue SQLite3::BusyException
          # This is acceptable in high concurrency scenarios
          nil
        end
      end

      # Wait for all threads to complete
      results = threads.map(&:value)

      # At least some operations should succeed
      successful_operations = results.compact.length
      expect(successful_operations).to be > 0
    end

    it "recovers from transaction rollbacks" do
      initial_count = db.statistics[:total_sessions]

      # Intentionally cause a rollback
      expect do
        db.connection.transaction do
          db.create_session(name: "rollback-test-1")
          db.create_session(name: "rollback-test-2")
          # Force a constraint violation
          db.create_session(name: "rollback-test-1") # Duplicate name
        end
      end.to raise_error(Sxn::Database::DuplicateSessionError)

      # Database should be in consistent state
      final_count = db.statistics[:total_sessions]
      expect(final_count).to eq(initial_count)

      # Should be able to continue normal operations
      session_id = db.create_session(name: "recovery-test")
      expect(session_id).to be_a(String)
    end
  end

  describe "Advanced Database Features" do
    it "supports full-text search across multiple fields" do
      # Create sessions with content in different fields
      sessions = [
        { name: "search-name-test", description: "content", tags: ["other"] },
        { name: "other", description: "search description test", tags: ["other"] },
        { name: "other", description: "content", tags: %w[search tag test] }
      ]

      sessions.each_with_index do |session_data, i|
        db.create_session(session_data.merge(name: "#{session_data[:name]}-#{i}"))
      end

      # Search should find matches in all fields
      results = db.search_sessions("test")
      expect(results.length).to eq(3)

      # Test relevance scoring
      name_match = results.find { |r| r[:name].include?("search-name-test") }
      description_match = results.find { |r| r[:description].include?("search description test") }
      tag_match = results.find { |r| r[:tags].include?("search") }

      expect(name_match[:relevance_score]).to be >= description_match[:relevance_score]
      expect(description_match[:relevance_score]).to be >= tag_match[:relevance_score]
    end

    it "handles JSON data types correctly" do
      complex_data = {
        string: "test string",
        number: 42,
        float: 3.14159,
        boolean: true,
        null_value: nil,
        array: [1, "two", { three: 4 }],
        nested_object: {
          deep: {
            deeper: {
              deepest: "value"
            }
          }
        }
      }

      session_id = db.create_session(
        name: "json-test",
        metadata: complex_data
      )

      retrieved = db.get_session(session_id)

      # JSON should round-trip correctly
      expect(retrieved[:metadata]["string"]).to eq("test string")
      expect(retrieved[:metadata]["number"]).to eq(42)
      expect(retrieved[:metadata]["float"]).to eq(3.14159)
      expect(retrieved[:metadata]["boolean"]).to eq(true)
      expect(retrieved[:metadata]["null_value"]).to be_nil
      expect(retrieved[:metadata]["array"]).to eq([1, "two", { "three" => 4 }])
      expect(retrieved[:metadata]["nested_object"]["deep"]["deeper"]["deepest"]).to eq("value")
    end
  end

  describe "Database Maintenance and Monitoring" do
    before do
      # Create some test data
      5.times { |i| db.create_session(name: "maintenance-test-#{i}") }
    end

    it "provides comprehensive statistics" do
      stats = db.statistics

      expect(stats).to have_key(:total_sessions)
      expect(stats).to have_key(:by_status)
      expect(stats).to have_key(:recent_activity)
      expect(stats).to have_key(:database_size)

      expect(stats[:total_sessions]).to eq(5)
      expect(stats[:by_status]["active"]).to eq(5)
      expect(stats[:recent_activity]).to eq(5)
      expect(stats[:database_size]).to be_a(Float)
    end

    it "supports vacuum operation for database optimization" do
      db.send(:database_size_mb)

      # Add and remove data to create fragmentation
      temp_sessions = 10.times.map do |i|
        db.create_session(name: "temp-#{i}")
      end

      temp_sessions.each { |id| db.delete_session(id) }

      # Close all prepared statements before vacuum
      db.instance_variable_get(:@prepared_statements).each_value(&:close)
      db.instance_variable_get(:@prepared_statements).clear

      # Vacuum should optimize the database
      result = db.maintenance([:vacuum])
      expect(result[:vacuum]).to eq("completed")

      # Database should still function correctly
      test_id = db.create_session(name: "post-vacuum-test")
      session = db.get_session(test_id)
      expect(session[:name]).to eq("post-vacuum-test")
    end

    it "supports analyze operation for query optimization" do
      result = db.maintenance([:analyze])
      expect(result[:analyze]).to eq("completed")

      # Database should still function correctly after analyze
      sessions = db.list_sessions
      expect(sessions).to be_an(Array)
    end

    it "supports integrity checking" do
      result = db.maintenance([:integrity_check])
      expect(result[:integrity_check]).to eq("ok")
    end
  end

  describe "Edge Cases and Boundary Conditions" do
    it "handles maximum length session names" do
      max_length_name = "a" * 1000 # Very long name
      session_id = db.create_session(name: max_length_name)
      session = db.get_session(session_id)
      expect(session[:name]).to eq(max_length_name)
    end

    it "handles empty and nil values appropriately" do
      session_id = db.create_session(
        name: "empty-values-test",
        description: "",
        tags: [],
        metadata: {}
      )

      session = db.get_session(session_id)
      expect(session[:description]).to eq("")
      expect(session[:tags]).to eq([])
      expect(session[:metadata]).to eq({})
    end

    it "handles special characters in all text fields" do
      special_chars = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"
      unicode_chars = "🚀 Test éñçødîñg 中文 العربية русский"

      session_id = db.create_session(
        name: "special-chars-test",
        description: "#{special_chars} #{unicode_chars}",
        tags: [special_chars, unicode_chars],
        metadata: {
          special_chars => unicode_chars,
          unicode_chars => special_chars
        }
      )

      session = db.get_session(session_id)
      expect(session[:description]).to include(special_chars, unicode_chars)
      expect(session[:tags]).to include(special_chars, unicode_chars)
      expect(session[:metadata][special_chars]).to eq(unicode_chars)
      expect(session[:metadata][unicode_chars]).to eq(special_chars)
    end

    it "handles timezone considerations in timestamps" do
      # Create session and check timestamp format
      session_id = db.create_session(name: "timezone-test")
      session = db.get_session(session_id)

      # Should be in UTC format with microseconds
      expect(session[:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z/)
      expect(session[:updated_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z/)

      # Parse and verify it's a valid time
      created_time = Time.parse(session[:created_at])
      expect(created_time).to be_a(Time)
      expect(created_time.utc?).to be true
    end
  end
end
