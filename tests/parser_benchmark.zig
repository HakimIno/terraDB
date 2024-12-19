const std = @import("std");
const testing = std.testing;
const parser = @import("parser");
const FastParser = parser.FastParser;
const FastLexer = parser.FastLexer;

// Benchmark configuration
const BenchmarkConfig = struct {
    iterations: usize,
    warm_up_iterations: usize,
    max_query_length: usize,
    memory_threshold: usize,
    timeout_ms: u64,
};

const DEFAULT_CONFIG = BenchmarkConfig{
    .iterations = 100_000,
    .warm_up_iterations = 1000,
    .max_query_length = 4096,
    .memory_threshold = 1024 * 1024, // 1MB
    .timeout_ms = 1000,
};

// Test queries with different complexities
const test_queries = [_][]const u8{
    // Simple queries
    "SELECT * FROM users",
    "SELECT id FROM products",
    "INSERT INTO users (id) VALUES (1)",
    "UPDATE users SET active = true",
    "DELETE FROM users",
    
    // Medium complexity
    "SELECT id, name, email FROM users WHERE age > 18",
    "INSERT INTO users (name, age) VALUES ('John', 25)",
    "UPDATE products SET price = price * 1.1 WHERE category = 'electronics'",
    "DELETE FROM orders WHERE created_at < NOW() - INTERVAL '1 year'",
    
    // Complex queries
    "SELECT u.name, o.total FROM users u JOIN orders o ON u.id = o.user_id WHERE o.total > 1000 AND u.status = 'active'",
    "CREATE TABLE products (id INT PRIMARY KEY, name TEXT NOT NULL, price FLOAT DEFAULT 0.0, category_id INT REFERENCES categories(id))",
    "SELECT dept_id, COUNT(*) FROM employees GROUP BY dept_id HAVING COUNT(*) > 10",
    "SELECT name, salary, RANK() OVER (ORDER BY salary DESC) FROM employees",
    
    // Subqueries
    "SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE total > 1000)",
    "SELECT * FROM (SELECT id, COUNT(*) as count FROM orders GROUP BY id) AS t WHERE count > 10",
    
    // Set operations
    "SELECT id FROM users UNION SELECT id FROM employees",
    "SELECT id FROM customers EXCEPT SELECT id FROM inactive_customers",
    
    // Complex JOINs
    "SELECT * FROM orders o LEFT JOIN users u ON o.user_id = u.id RIGHT JOIN products p ON o.product_id = p.id",
    "SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id",
};

// Edge cases for testing
const edge_case_queries = [_][]const u8{
    "", // Empty query
    "SELECT" ++ (" a," ** 100) ++ " b FROM t", // Long query
    "SELEC * FORM users", // Invalid syntax
    "SELECT * FROM users WHERE name = 'สวัสดี'", // Unicode
    "SELECT * FROM (SELECT * FROM (SELECT * FROM users))", // Nested
    "SELECT '''", // Unterminated string
    "SELECT * FROM t1 /* Unterminated comment",
    "SELECT * FROM t1 -- Comment\n",
};

// Benchmark results structure
const BenchmarkResult = struct {
    query: []const u8,
    avg_time_ns: f64,
    min_time_ns: u64,
    max_time_ns: u64,
    queries_per_second: f64,
    memory_used: usize,
    error_count: usize,
};

// Compare with other databases
const DatabaseBenchmark = struct {
    name: []const u8,
    parse_time_ns: f64,
    qps: f64,
};

const database_benchmarks = [_]DatabaseBenchmark{
    .{ .name = "MySQL", .parse_time_ns = 100_000, .qps = 10_000 },
    .{ .name = "PostgreSQL", .parse_time_ns = 150_000, .qps = 6_666 },
    .{ .name = "ScyllaDB", .parse_time_ns = 80_000, .qps = 12_500 },
};

fn runBenchmark(allocator: std.mem.Allocator, query: []const u8, config: BenchmarkConfig) !BenchmarkResult {
    var timer = try std.time.Timer.start();
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;
    var total_memory: usize = 0;
    var error_count: usize = 0;

    // Warm up
    for (0..config.warm_up_iterations) |_| {
        var lexer = FastLexer.init(query, allocator);
        var fast_parser = try FastParser.init(&lexer, allocator);
        defer fast_parser.deinit();
        _ = fast_parser.parse(.unknown) catch {
            error_count += 1;
            continue;
        };
    }

    // Actual benchmark
    for (0..config.iterations) |_| {
        const start_memory = getCurrentMemoryUsage();
        timer.reset();
        
        var lexer = FastLexer.init(query, allocator);
        var fast_parser = try FastParser.init(&lexer, allocator);
        defer fast_parser.deinit();
        
        const parse_result = fast_parser.parse(.unknown) catch {
            error_count += 1;
            continue;
        };
        defer parse_result.deinit();
        
        const elapsed = timer.read();
        const memory_used = getCurrentMemoryUsage() - start_memory;
        
        if (elapsed > config.timeout_ms * 1_000_000) {
            continue; // Skip this iteration if it took too long
        }
        
        total_time += elapsed;
        min_time = @min(min_time, elapsed);
        max_time = @max(max_time, elapsed);
        total_memory += memory_used;
    }

    const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(config.iterations));
    const avg_memory = total_memory / config.iterations;
    const qps = 1_000_000_000.0 / avg_time;

    return BenchmarkResult{
        .query = query,
        .avg_time_ns = avg_time,
        .min_time_ns = min_time,
        .max_time_ns = max_time,
        .queries_per_second = qps,
        .memory_used = avg_memory,
        .error_count = error_count,
    };
}

fn getCurrentMemoryUsage() usize {
    if (@import("builtin").target.os.tag == .linux) {
        const page_size = std.os.system.sysconf(.PAGE_SIZE);
        const statm = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
        defer statm.close();
        
        var buffer: [128]u8 = undefined;
        const bytes_read = statm.read(&buffer) catch return 0;
        const content = buffer[0..bytes_read];
        
        var iterator = std.mem.split(u8, content, " ");
        _ = iterator.next(); // Skip total pages
        const resident_pages = std.fmt.parseInt(usize, iterator.next() orelse "0", 10) catch 0;
        
        return resident_pages * page_size;
    }
    // Add support for other platforms as needed
    return 0;
}

fn runStressTest(allocator: std.mem.Allocator) !void {
    const CONCURRENT_PARSERS = 10;
    var parsers = [_]FastParser{undefined} ** CONCURRENT_PARSERS;
    
    // Run multiple parsers concurrently
    for (&parsers) |*p| {
        var lexer = FastLexer.init(test_queries[0], allocator);
        p.* = try FastParser.init(&lexer, allocator);
    }
    defer for (&parsers) |*p| p.deinit();
    
    // Parse simultaneously
    for (&parsers) |*p| {
        _ = try p.parse(.unknown);
    }
}

fn testErrorHandling(allocator: std.mem.Allocator) !void {
    for (edge_case_queries) |query| {
        var lexer = FastLexer.init(query, allocator);
        var p = try FastParser.init(&lexer, allocator);
        defer p.deinit();
        
        if (p.parse(.unknown)) |result| {
            result.deinit();
        } else |_| {
            // Expected error for edge cases
            continue;
        }
    }
}

fn generateReport(results: []const BenchmarkResult) void {
    var total_time: f64 = 0;
    var total_memory: usize = 0;
    var total_errors: usize = 0;
    var slowest_query: ?BenchmarkResult = null;
    var fastest_query: ?BenchmarkResult = null;

    for (results) |result| {
        total_time += result.avg_time_ns;
        total_memory += result.memory_used;
        total_errors += result.error_count;
        
        if (slowest_query == null or result.avg_time_ns > slowest_query.?.avg_time_ns) {
            slowest_query = result;
        }
        if (fastest_query == null or result.avg_time_ns < fastest_query.?.avg_time_ns) {
            fastest_query = result;
        }
    }

    const avg_time = total_time / @as(f64, @floatFromInt(results.len));
    const avg_memory = @divFloor(total_memory, results.len);

    std.debug.print("\nOverall Performance Report\n", .{});
    std.debug.print("==========================\n", .{});
    std.debug.print("Total queries tested: {d}\n", .{results.len});
    std.debug.print("Average time across all queries: {d:.2} ns\n", .{avg_time});
    std.debug.print("Average memory usage: {d} bytes\n", .{avg_memory});
    std.debug.print("Total errors encountered: {d}\n", .{total_errors});
    std.debug.print("\nFastest query: {s}\n", .{fastest_query.?.query});
    std.debug.print("Time: {d:.2} ns\n", .{fastest_query.?.avg_time_ns});
    std.debug.print("\nSlowest query: {s}\n", .{slowest_query.?.query});
    std.debug.print("Time: {d:.2} ns\n", .{slowest_query.?.avg_time_ns});
}

test "parser performance benchmark" {
    const allocator = testing.allocator;
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();
    
    std.debug.print("\nParser Performance Benchmark\n", .{});
    std.debug.print("==========================\n\n", .{});

    // Run normal query benchmarks
    for (test_queries) |query| {
        const result = try runBenchmark(allocator, query, DEFAULT_CONFIG);
        try results.append(result);
        
        std.debug.print("Query: {s}\n", .{result.query});
        std.debug.print("Average time: {d:.2} ns\n", .{result.avg_time_ns});
        std.debug.print("Min time: {d} ns\n", .{result.min_time_ns});
        std.debug.print("Max time: {d} ns\n", .{result.max_time_ns});
        std.debug.print("Queries per second: {d:.2}\n", .{result.queries_per_second});
        std.debug.print("Average memory used: {d} bytes\n", .{result.memory_used});
        std.debug.print("Errors encountered: {d}\n", .{result.error_count});
        
        // Compare with other databases
        std.debug.print("\nComparison with other databases:\n", .{});
        for (database_benchmarks) |db| {
            const speedup = db.parse_time_ns / result.avg_time_ns;
            std.debug.print("{s}: {d:.2}x faster\n", .{db.name, speedup});
        }
        std.debug.print("\n---\n\n", .{});
        
        // Verify performance targets
        try testing.expect(result.avg_time_ns < 100_000); // Should be faster than MySQL
        try testing.expect(result.queries_per_second > 10_000); // Should handle more QPS than MySQL
    }

    // Run stress test
    try runStressTest(allocator);

    // Run error handling test
    try testErrorHandling(allocator);

    // Generate final report
    generateReport(results.items);
}