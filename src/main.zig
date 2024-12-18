// src/main.zig
const std = @import("std");
const Page = @import("storage/page.zig").Page;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test creating and writing to a page
    var page = try Page.init(allocator, .data, 1);
    defer page.deinit();

    try page.write(32, "Test data");
    const data = try page.read(32, 9);
    std.debug.print("Read data: {s}\n", .{data});
}