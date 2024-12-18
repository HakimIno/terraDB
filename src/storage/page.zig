const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const builtin = @import("builtin");
const x86 = std.Target.x86;

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
    data: [PAGE_SIZE - @sizeOf(PageHeader)]u8 align(8),
    allocator: Allocator,

    // Use better error handling
    const Error = error{
        PageOverflow,
        InvalidOffset,
        InvalidLength,
        ChecksumMismatch,
        InvalidFreeSpaceOffset,
    };

    // Optimized init with fixed-size array
    pub fn init(allocator: Allocator, page_type: PageType, page_id: u32) !Page {
        var page = Page{
            .header = PageHeader.init(page_type, page_id),
            .data = undefined,
            .allocator = allocator,
        };
        @memset(&page.data, 0);
        return page;
    }

    // ไม่จำเป็นต้องมี deinit เพราะใช้ fixed-size array แล้ว
    pub fn deinit(self: *Page) void {
        _ = self;
    }

    // Optimized write with minimal overhead
    pub inline fn write(self: *Page, offset: u16, data_in: []const u8) Error!void {
        if (offset < @sizeOf(PageHeader) or offset + data_in.len > PAGE_SIZE) 
            return error.InvalidOffset;
        
        const write_offset = offset - @sizeOf(PageHeader);
        
        // Ultra-fast path for tiny writes (<=8 bytes)
        if (data_in.len <= 8) {
            @memcpy(self.data[write_offset..][0..data_in.len], data_in);
            self.header.free_space_offset = @intCast(offset + data_in.len);
            return;
        }

        // Fast path for small writes (<=32 bytes)
        if (data_in.len <= 32) {
            const Vec = @Vector(32, u8);
            const src = @as(*align(1) const Vec, @ptrCast(&data_in[0]));
            const dst = @as(*align(1) Vec, @ptrCast(&self.data[write_offset]));
            dst.* = src.*;
            self.header.free_space_offset = @intCast(offset + data_in.len);
            return;
        }

        // Use prefetch for larger writes
        if (data_in.len > 64) {
            const ptr = &self.data[write_offset + 64];
            asm volatile("prefetchnta (%[ptr])"
                :
                : [ptr] "r" (ptr)
                : "memory"
            );
        }

        // Aligned copy for larger writes
        @memcpy(self.data[write_offset..][0..data_in.len], data_in);
        self.header.free_space_offset = @intCast(offset + data_in.len);
    }

    // Ultra-optimized read
    pub inline fn read(self: *const Page, offset: u16, len: usize) Error![]const u8 {
        if (offset < @sizeOf(PageHeader) or offset + len > PAGE_SIZE) 
            return error.InvalidOffset;
        
        const read_offset = offset - @sizeOf(PageHeader);
        
        // Use prefetch for large reads
        if (len > 64) {
            const ptr = &self.data[read_offset + 64];
            asm volatile("prefetchnta (%[ptr])"
                :
                : [ptr] "r" (ptr)
                : "memory"
            );
        }

        return self.data[read_offset..][0..len];
    }

    // Optimized serialization with error handling
    pub inline fn serialize(self: *const Page) Error![PAGE_SIZE]u8 {
        var buffer: [PAGE_SIZE]u8 align(8) = undefined;
        
        // Copy header
        @memcpy(buffer[0..@sizeOf(PageHeader)], @as([*]const u8, @ptrCast(&self.header))[0..@sizeOf(PageHeader)]);
        
        // Copy data
        @memcpy(buffer[@sizeOf(PageHeader)..], &self.data);
        
        // Calculate checksum before returning
        var temp_header = @as(*PageHeader, @ptrCast(@alignCast(&buffer[0])));
        temp_header.calculateChecksum();
        
        return buffer;
    }

    // Optimized deserialization with error handling
    pub inline fn deserialize(allocator: Allocator, buffer: *align(8) const [PAGE_SIZE]u8) !Page {
        const header = @as(*const PageHeader, @ptrCast(@alignCast(&buffer[0]))).*;
        
        // Verify checksum
        if (!header.verifyChecksum()) {
            return error.ChecksumMismatch;
        }
        
        var page = Page{
            .header = header,
            .data = undefined,
            .allocator = allocator,
        };
        
        // Copy data
        @memcpy(&page.data, buffer[@sizeOf(PageHeader)..][0..page.data.len]);
        
        return page;
    }

    // Use comptime for constant calculations
    pub inline fn getFreeSpace(self: Page) u16 {
        return @intCast(PAGE_SIZE - self.header.free_space_offset);
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

    // เพิ่มฟังก์ชันใหม่สำหรับ zero-copy serialization
    pub fn serializeInto(self: *const Page, buffer: *[PAGE_SIZE]u8) void {
        const header_bytes = std.mem.asBytes(&self.header);
        @memcpy(buffer[0..@sizeOf(PageHeader)], header_bytes);
        @memcpy(buffer[@sizeOf(PageHeader)..], self.data);
    }

    // เพิมฟังก์ชันใหม่สำหรับ zero-copy deserialization
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