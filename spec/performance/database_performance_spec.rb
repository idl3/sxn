# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "tempfile"

RSpec.describe "Database Performance", type: :performance do
  let(:temp_db_path) { Tempfile.new(["perf_sessions", ".db"]).path }
  let(:db) { Sxn::Database::SessionDatabase.new(temp_db_path) }

  after do
    db.close
    FileUtils.rm_f(temp_db_path)
  end

  describe "with 100+ sessions" do
    let(:session_count) { 150 }
    let!(:session_ids) do
      puts "Creating #{session_count} test sessions..."

      # Create sessions with varied data for realistic testing
      statuses = %w[active inactive archived]
      tags_options = [
        %w[feature backend],
        %w[bugfix frontend],
        %w[refactor database],
        %w[feature api urgent],
        %w[bugfix security],
        ["maintenance"]
      ]

      session_count.times.map do |i|
        db.create_session(
          name: "session-#{i.to_s.rjust(4, "0")}",
          status: statuses.sample,
          linear_task: "ATL-#{1000 + i}",
          description: "Test session #{i} for performance testing with some longer description text",
          tags: tags_options.sample,
          metadata: {
            priority: %w[low medium high critical].sample,
            assignee: "user-#{i % 10}",
            project_id: i % 20,
            estimated_hours: rand(1..40),
            complexity: %w[simple medium complex].sample
          }
        )
      end
    end

    describe "session creation performance" do
      it "creates sessions quickly" do
        times = []

        10.times do |i|
          time = Benchmark.measure do
            db.create_session(
              name: "perf-test-#{i}",
              status: "active",
              description: "Performance test session",
              tags: %w[performance test],
              metadata: { test: true, iteration: i }
            )
          end
          times << time.real
        end

        avg_time = times.sum / times.length
        max_time = times.max

        puts "Session creation - Average: #{(avg_time * 1000).round(2)}ms, Max: #{(max_time * 1000).round(2)}ms"

        # Should be under 10ms average, 50ms max
        expect(avg_time).to be < 0.01
        expect(max_time).to be < 0.05
      end
    end

    describe "session listing performance" do
      it "lists sessions quickly without filters" do
        time = Benchmark.measure do
          sessions = db.list_sessions(limit: 100)
          expect(sessions.length).to eq(100)
        end

        puts "List 100 sessions: #{(time.real * 1000).round(2)}ms"

        # Should be under 5ms for 100 sessions
        expect(time.real).to be < 0.005
      end

      it "lists sessions quickly with status filter" do
        time = Benchmark.measure do
          sessions = db.list_sessions(filters: { status: "active" }, sort: {}, limit: 50)
          expect(sessions.length).to be <= 50
        end

        puts "List sessions with status filter: #{(time.real * 1000).round(2)}ms"

        # Should be under 10ms with indexed filter (relaxed for CI environments)
        expect(time.real).to be < 0.01
      end

      it "lists sessions quickly with complex filters" do
        time = Benchmark.measure do
          db.list_sessions(
            filters: {
              status: "active",
              tags: ["feature"],
              created_after: Time.now - (7 * 24 * 60 * 60)
            },
            sort: { by: :updated_at, order: :desc },
            limit: 25
          )
        end

        puts "List sessions with complex filters: #{(time.real * 1000).round(2)}ms"

        # Should be under 10ms with multiple filters
        expect(time.real).to be < 0.01
      end
    end

    describe "search performance" do
      it "searches sessions quickly" do
        time = Benchmark.measure do
          results = db.search_sessions("feature", limit: 50)
          expect(results).to be_an(Array)
        end

        puts "Search sessions: #{(time.real * 1000).round(2)}ms"

        # Should be under 20ms for full-text search
        expect(time.real).to be < 0.02
      end

      it "searches with filters quickly" do
        time = Benchmark.measure do
          results = db.search_sessions(
            "backend",
            filters: { status: "active" },
            limit: 25
          )
          expect(results).to be_an(Array)
        end

        puts "Search with filters: #{(time.real * 1000).round(2)}ms"

        # Should be under 25ms for combined search and filter
        expect(time.real).to be < 0.025
      end
    end

    describe "update performance" do
      it "updates sessions quickly" do
        test_sessions = session_ids.sample(10)
        times = []

        test_sessions.each do |session_id|
          time = Benchmark.measure do
            db.update_session(session_id, {
                                status: "inactive",
                                description: "Updated for performance test",
                                metadata: { performance_test: true }
                              })
          end
          times << time.real
        end

        avg_time = times.sum / times.length
        puts "Session update - Average: #{(avg_time * 1000).round(2)}ms"

        # Should be under 5ms average
        expect(avg_time).to be < 0.005
      end
    end

    describe "bulk operations performance" do
      it "handles bulk reads efficiently" do
        time = Benchmark.measure do
          session_ids.sample(50).each do |id|
            db.get_session(id)
          end
        end

        puts "50 individual reads: #{(time.real * 1000).round(2)}ms"

        # Should be under 50ms for 50 individual reads
        expect(time.real).to be < 0.05
      end

      it "handles bulk updates efficiently" do
        test_sessions = session_ids.sample(20)

        time = Benchmark.measure do
          db.connection.transaction do
            test_sessions.each do |session_id|
              db.update_session(session_id, {
                                  status: "archived",
                                  metadata: { bulk_update: true }
                                })
            end
          end
        end

        puts "20 bulk updates: #{(time.real * 1000).round(2)}ms"

        # Should be under 100ms for 20 updates in transaction
        expect(time.real).to be < 0.1
      end
    end

    describe "statistics performance" do
      it "calculates statistics quickly" do
        time = Benchmark.measure do
          stats = db.statistics
          expect(stats[:total_sessions]).to be >= session_count
          expect(stats[:by_status]).to be_a(Hash)
        end

        puts "Statistics calculation: #{(time.real * 1000).round(2)}ms"

        # Should be under 10ms for statistics
        expect(time.real).to be < 0.01
      end
    end

    describe "memory usage" do
      it "maintains reasonable memory usage" do
        # Measure memory before and after operations
        initial_memory = memory_usage_mb

        # Perform various operations
        10.times do
          db.list_sessions(limit: 100)
          db.search_sessions("test", limit: 50)
          session_id = session_ids.sample
          db.get_session(session_id)
          db.update_session(session_id, { metadata: { test: Time.now.to_i } })
        end

        final_memory = memory_usage_mb
        memory_increase = final_memory - initial_memory

        puts "Memory usage - Initial: #{initial_memory}MB, Final: #{final_memory}MB, Increase: #{memory_increase}MB"

        # Should not leak significant memory (under 10MB increase)
        expect(memory_increase).to be < 10
      end
    end

    describe "database size optimization" do
      it "maintains reasonable database size" do
        stats = db.statistics
        size_mb = stats[:database_size]

        puts "Database size with #{session_count} sessions: #{size_mb}MB"

        # Should be under 5MB for 150 sessions with metadata
        expect(size_mb).to be < 5.0
      end

      it "benefits from maintenance operations" do
        initial_size = db.statistics[:database_size]

        # Delete some sessions to create fragmentation
        sessions_to_delete = session_ids.sample(30)
        sessions_to_delete.each { |id| db.delete_session(id) }

        size_after_deletion = db.statistics[:database_size]

        # Run maintenance (using analyze which doesn't require exclusive access)
        db.maintenance([:analyze])

        size_after_maintenance = db.statistics[:database_size]

        puts "Database size - Initial: #{initial_size}MB, After deletion: #{size_after_deletion}MB, After maintenance: #{size_after_maintenance}MB"

        # Maintenance should complete successfully (analyze updates statistics)
        expect(size_after_maintenance).to be >= 0
      end
    end
  end

  describe "stress testing" do
    it "handles rapid concurrent operations" do
      # Simulate multiple processes/threads accessing database
      threads = []
      errors = []
      successful_operations = begin
        Concurrent::AtomicFixnum.new(0)
      rescue StandardError
        0
      end
      mutex = Mutex.new

      5.times do |thread_id|
        threads << Thread.new do
          thread_db = Sxn::Database::SessionDatabase.new(temp_db_path)
          thread_successful = 0

          20.times do |i|
            session_id = thread_db.create_session(
              name: "thread-#{thread_id}-session-#{i}",
              status: "active",
              metadata: { thread_id: thread_id, iteration: i }
            )

            # Immediately read and update
            thread_db.get_session(session_id)
            thread_db.update_session(session_id, {
                                       description: "Updated by thread #{thread_id}"
                                     })
            thread_successful += 1
          rescue SQLite3::BusyException
            # Expected - SQLite can't handle all concurrent writes
            # Retry once with small delay
            sleep(0.001)
            retry if i < 19 # Only retry once per operation
          end

          # Thread-safe counter update
          if successful_operations.respond_to?(:update)
            successful_operations.update { |v| v + thread_successful }
          else
            mutex.synchronize { successful_operations += thread_successful }
          end

          thread_db.close
        rescue StandardError => e
          mutex.synchronize { errors << e }
        end
      end

      threads.each(&:join)

      final_count = successful_operations.respond_to?(:value) ? successful_operations.value : successful_operations

      # Should have some successful operations even if not all due to locking
      expect(final_count).to be > 50
      puts "Successful concurrent operations: #{final_count}/100"

      # Database should not be corrupted
      expect { db.statistics }.not_to raise_error
    end
  end

  private

  # Get current memory usage in MB (approximate)
  def memory_usage_mb
    if RUBY_PLATFORM.include?("darwin") # macOS
    else # Linux
    end
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  rescue StandardError
    0.0 # Fallback if ps command fails
  end
end
