const std = @import("std");
const testing = std.testing;
const Page = @import("storage").Page;
const PageType = @import("storage").PageType;
const Timer = std.time.Timer;
const MemoryPool = @import("storage").MemoryPool;
const PageCache = @import("storage").PageCache;
const PAGE_SIZE = 4096;

// จำนวนรอบในการทดสอบ
const ITERATIONS = 1_000_000;

test "benchmark page operations" {
    const allocator = testing.allocator;
    var timer = try Timer.start();
    var total_write_time: u64 = 0;
    var total_read_time: u64 = 0;
    var total_serialize_time: u64 = 0;
    var total_deserialize_time: u64 = 0;

    // ข้อมูลทดสอบ
    const test_data = "Hello, Database! This is a test string for benchmarking.";
    
    // ทดสอบการเขียนและอ่าน
    {
        var page = try Page.init(allocator, .data, 1);
        defer page.deinit();

        // วัดเวลาการเขียน
        timer.reset();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            try page.write(32, test_data);
            total_write_time += timer.lap();
        }

        // วัดเวลาการอ่าน
        timer.reset();
        i = 0;
        while (i < ITERATIONS) : (i += 1) {
            _ = try page.read(32, test_data.len);
            total_read_time += timer.lap();
        }

        // วัดเวลา serialization
        timer.reset();
        i = 0;
        while (i < ITERATIONS) : (i += 1) {
            var serialized: [4096]u8 align(8) = try page.serialize();
            total_serialize_time += timer.lap();

            // วัดเวลา deserialization
            timer.reset();
            var deserialized = try Page.deserialize(allocator, &serialized);
            total_deserialize_time += timer.lap();
            deserialized.deinit();
        }
    }

    // แสดงผลลัพธ์
    std.debug.print("\n=== Page Performance Benchmark ===\n", .{});
    const avg_write = @as(f64, @floatFromInt(total_write_time)) / ITERATIONS;
    const avg_read = @as(f64, @floatFromInt(total_read_time)) / ITERATIONS;
    const avg_serialize = @as(f64, @floatFromInt(total_serialize_time)) / ITERATIONS;
    const avg_deserialize = @as(f64, @floatFromInt(total_deserialize_time)) / ITERATIONS;
    
    std.debug.print("Average write time: {d:.2} ns\n", .{avg_write});
    std.debug.print("Average read time: {d:.2} ns\n", .{avg_read});
    std.debug.print("Average serialize time: {d:.2} ns\n", .{avg_serialize});
    std.debug.print("Average deserialize time: {d:.2} ns\n", .{avg_deserialize});
    std.debug.print("Total operations: {d}\n", .{ITERATIONS});
    std.debug.print("\n", .{});

    // เพิ่ม expectation เพื่อให้แน่ใจว่า test จะไม่ถูก optimize ออก
    try testing.expect(avg_write > 0);
    try testing.expect(avg_read > 0);
    try testing.expect(avg_serialize > 0);
    try testing.expect(avg_deserialize > 0);
} 

test "benchmark with optimizations" {
    const allocator = testing.allocator;
    var timer = try Timer.start();
    var total_pool_time: u64 = 0;
    var total_direct_time: u64 = 0;
    
    // สร้าง memory pool
    var memory_pool = try MemoryPool.init(allocator, 10, PAGE_SIZE);
    defer memory_pool.deinit();

    // สร้าง page cache
    var page_cache = try PageCache.init(allocator, 1000, &memory_pool);
    defer page_cache.deinit();

    const test_data = "Hello, Database! This is a test string for benchmarking.";

    // ทดสอบ Memory Pool
    {
        timer.reset();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            const buffer = try memory_pool.acquire();
            var page = try Page.init(allocator, .data, 1);
            defer page.deinit();

            try page.write(32, test_data);
            var serialized = try page.serialize();
            @memcpy(buffer[0..serialized.len], &serialized);

            total_pool_time += timer.lap();
            memory_pool.release(buffer);
        }
    }

    // ทดสอบ Direct Allocation
    {
        timer.reset();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            const buffer = try allocator.alignedAlloc(u8, 8, PAGE_SIZE);
            var page = try Page.init(allocator, .data, 1);
            defer page.deinit();

            try page.write(32, test_data);
            var serialized = try page.serialize();
            @memcpy(buffer[0..serialized.len], &serialized);

            total_direct_time += timer.lap();
            allocator.free(buffer);
        }
    }

    // แสดงผลลัพธ์
    std.debug.print("\n=== Memory Pool vs Direct Allocation Benchmark ===\n", .{});
    const avg_pool = @as(f64, @floatFromInt(total_pool_time)) / ITERATIONS;
    const avg_direct = @as(f64, @floatFromInt(total_direct_time)) / ITERATIONS;
    
    std.debug.print("Memory Pool average time: {d:.2} ns\n", .{avg_pool});
    std.debug.print("Direct allocation average time: {d:.2} ns\n", .{avg_direct});
    std.debug.print("Improvement: {d:.2}x\n", .{avg_direct / avg_pool});
    std.debug.print("Total operations: {d}\n\n", .{ITERATIONS});

    try testing.expect(avg_pool > 0);
    try testing.expect(avg_direct > 0);
} 