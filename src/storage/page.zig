const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

// Constants using comptime for better optimization
pub const PAGE_SIZE: comptime_int = 4096;
pub const PAGE_HEADER_SIZE: comptime_int = @sizeOf(PageHeader);
pub const MAX_DATA_SIZE: comptime_int = PAGE_SIZE - PAGE_HEADER_SIZE;

// Use packed struct for PageType to optimize memory
pub const PageType = enum(u8) {
    data,
    index,
    overflow,
    free,
    _,
};

// Use packed struct for better memory layout
pub const PageHeader = extern struct {
    page_type: PageType,
    flags: u8,  // Added flags for future use
    item_count: u16,
    free_space_offset: u16,
    page_id: u32,
    parent_id: u32,
    next_page: u32,
    prev_page: u32,
    checksum: u32,
    
    // Use inline for small functions
    pub inline fn init(page_type: PageType, page_id: u32) PageHeader {
        return .{
            .page_type = page_type,
            .flags = 0,
            .item_count = 0,
            .free_space_offset = PAGE_HEADER_SIZE,
            .page_id = page_id,
            .parent_id = 0,
            .next_page = 0,
            .prev_page = 0,
            .checksum = 0,
        };
    }

    // Optimize checksum calculation
    pub fn calculateChecksum(self: *PageHeader) void {
        var hasher = std.hash.Wyhash.init(0);
        const bytes = std.mem.asBytes(self)[0..@sizeOf(PageHeader) - 4];
        hasher.update(bytes);
        self.checksum = @truncate(hasher.final());
    }

    pub inline fn verifyChecksum(self: PageHeader) bool {
        var temp = self;
        temp.calculateChecksum();
        return temp.checksum == self.checksum;
    }
};

// Use alignment for better memory access
pub const Page = struct {
    header: PageHeader align(8),
    data: []align(8) u8,
    allocator: Allocator,

    // Use better error handling
    const Error = error{
        PageOverflow,
        InvalidOffset,
        InvalidLength,
        ChecksumMismatch,
        InvalidFreeSpaceOffset,
    };

    pub fn init(allocator: Allocator, page_type: PageType, page_id: u32) !Page {
        // Allocate exactly PAGE_SIZE - @sizeOf(PageHeader) bytes for data
        const data_size = PAGE_SIZE - @sizeOf(PageHeader);
        const data = try allocator.alignedAlloc(u8, 8, data_size);
        @memset(data, 0);
        
        var header = PageHeader.init(page_type, page_id);
        header.calculateChecksum();

        return .{
            .header = header,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Page) void {
        self.allocator.free(self.data);
    }

    // Optimize write operation
    pub fn write(self: *Page, offset: u16, data_in: []const u8) Error!void {
        if (@sizeOf(PageHeader) > offset) return error.InvalidOffset;
        if (data_in.len > self.data.len or offset + data_in.len > PAGE_SIZE) {
            return error.PageOverflow;
        }

        const write_offset = offset - @sizeOf(PageHeader);
        if (@hasDecl(std.simd, "copy")) {
            std.simd.copy(self.data[write_offset..][0..data_in.len], data_in);
        } else {
            @memcpy(self.data[write_offset..][0..data_in.len], data_in);
        }
        self.header.free_space_offset = @intCast(offset + data_in.len);
        self.header.calculateChecksum();
    }

    // Optimize read operation with better error checking
    pub fn read(self: Page, offset: u16, len: usize) Error![]const u8 {
        if (@sizeOf(PageHeader) > offset) return error.InvalidOffset;
        if (len == 0) return error.InvalidLength;
        if (len > self.data.len or offset + len > PAGE_SIZE) {
            return error.PageOverflow;
        }

        const read_offset = offset - @sizeOf(PageHeader);
        return self.data[read_offset..][0..len];
    }

    // Use comptime for constant calculations
    pub inline fn getFreeSpace(self: Page) u16 {
        return @intCast(PAGE_SIZE - self.header.free_space_offset);
    }

    // Optimize serialization
    pub fn serialize(self: Page) ![PAGE_SIZE]u8 {
        var buffer: [PAGE_SIZE]u8 align(8) = undefined;
        const header_bytes = std.mem.asBytes(&self.header);
        
        @memcpy(buffer[0..header_bytes.len], header_bytes);
        @memcpy(buffer[@sizeOf(PageHeader)..], self.data);
        
        return buffer;
    }

    // Optimize deserialization with better error handling
    pub fn deserialize(allocator: Allocator, buffer: *align(8) const [PAGE_SIZE]u8) !Page {
        const header = @as(*const PageHeader, @ptrCast(@alignCast(&buffer[0]))).*;
        
        if (!header.verifyChecksum()) return error.ChecksumMismatch;

        var page = try Page.init(allocator, header.page_type, header.page_id);
        page.header = header;
        @memcpy(page.data, buffer[@sizeOf(PageHeader)..][0..page.data.len]);

        return page;
    }

    // Optimize defragmentation
    pub fn defragment(self: *Page) !void {
        const valid_data_size = self.header.free_space_offset - PAGE_HEADER_SIZE;
        if (valid_data_size == 0) return;

        const temp_data = try self.allocator.alignedAlloc(u8, 8, valid_data_size);
        defer self.allocator.free(temp_data);

        @memcpy(temp_data, self.data[0..valid_data_size]);
        @memset(self.data, 0);
        @memcpy(self.data[0..valid_data_size], temp_data);

        self.header.calculateChecksum();
    }

    // Add fast validation
    pub inline fn validate(self: Page) Error!void {
        if (!self.header.verifyChecksum()) return error.ChecksumMismatch;
        if (self.header.free_space_offset > PAGE_SIZE or 
            self.header.free_space_offset < PAGE_HEADER_SIZE) {
            return error.InvalidFreeSpaceOffset;
        }
    }

    // เพิ่มฟังก์ชันใหม่สำหร���บ zero-copy serialization
    pub fn serializeInto(self: *const Page, buffer: *[PAGE_SIZE]u8) void {
        const header_bytes = std.mem.asBytes(&self.header);
        @memcpy(buffer[0..@sizeOf(PageHeader)], header_bytes);
        @memcpy(buffer[@sizeOf(PageHeader)..], self.data);
    }

    // เพิ่มฟังก์ชันใหม่สำหรับ zero-copy deserialization
    pub fn deserializeFrom(allocator: Allocator, buffer: *align(8) const [PAGE_SIZE]u8) !Page {
        const header = @as(*const PageHeader, @ptrCast(@alignCast(&buffer[0]))).*;
        if (!header.verifyChecksum()) return error.ChecksumMismatch;

        var page = try Page.init(allocator, header.page_type, header.page_id);
        page.header = header;
        @memcpy(page.data, buffer[@sizeOf(PageHeader)..]);
        return page;
    }
};

pub const MemoryPool = @import("memory_pool.zig").MemoryPool;