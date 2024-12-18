// tests/page_test.zig
const std = @import("std");
const testing = std.testing;
const Page = @import("storage").Page;
const PageType = @import("storage").PageType;
const PAGE_SIZE = @import("storage").PAGE_SIZE;

test "page basic operations" {
    const allocator = testing.allocator;
    
    // Test page creation
    var page = try Page.init(allocator, .data, 1);
    defer page.deinit();

    // Test write
    const test_data = "Hello, Database!";
    try page.write(32, test_data);

    // Test read
    const read_data = try page.read(32, test_data.len);
    try testing.expectEqualSlices(u8, test_data, read_data);

    // Test free space
    const expected_free = PAGE_SIZE - 32 - test_data.len;
    try testing.expectEqual(expected_free, page.getFreeSpace());
}

test "page serialization" {
    const allocator = testing.allocator;
    var page = try Page.init(allocator, .data, 1);
    defer page.deinit();

    const test_data = "Test Data";
    try page.write(32, test_data);

    // Test serialize/deserialize
    // Ensure serialized buffer is aligned
    var serialized: [PAGE_SIZE]u8 align(8) = try page.serialize();
    var deserialized = try Page.deserialize(allocator, &serialized);
    defer deserialized.deinit();

    const read_data = try deserialized.read(32, test_data.len);
    try testing.expectEqualSlices(u8, test_data, read_data);
}