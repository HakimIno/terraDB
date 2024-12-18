const std = @import("std");
const os = std.os;
const page_mod = @import("page.zig");
const Page = page_mod.Page;
const PageID = u32;
const PAGE_SIZE = page_mod.PAGE_SIZE;

pub const Pager = struct {
    file: std.fs.File,
    page_cache: std.AutoHashMap(PageID, *Page),
    allocator: std.mem.Allocator,
    file_size: u64,
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Pager {
        // Open file with normal mode first
        const file = try std.fs.cwd().createFile(path, .{
            .read = true,
            .truncate = false,
        });
        
        return Pager{
            .file = file,
            .page_cache = std.AutoHashMap(PageID, *Page).init(allocator),
            .allocator = allocator,
            .file_size = 0,
        };
    }
    
    pub fn deinit(self: *Pager) void {
        var it = self.page_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.page_cache.deinit();
        self.file.close();
    }
    
    pub fn getPage(self: *Pager, page_id: PageID) !*Page {
        // Check cache first
        if (self.page_cache.get(page_id)) |cached_page| {
            return cached_page;
        }
        
        // Calculate offset
        const offset = page_id * @sizeOf(Page);
        
        // Read page from file
        var buffer: [PAGE_SIZE]u8 align(8) = undefined;
        const bytes_read = try self.file.preadAll(&buffer, offset);
        if (bytes_read == 0) {
            // Create new page if not found
            const page_ptr = try self.allocator.create(Page);
            page_ptr.* = try Page.init(self.allocator, .data, page_id);
            try self.page_cache.put(page_id, page_ptr);
            return page_ptr;
        }
        
        // Deserialize page
        const loaded_page = try Page.deserialize(self.allocator, @alignCast(&buffer));
        const page_ptr = try self.allocator.create(Page);
        page_ptr.* = loaded_page;
        try self.page_cache.put(page_id, page_ptr);
        
        return page_ptr;
    }
    
    pub fn writePage(self: *Pager, page_id: PageID) !void {
        const cached_page = self.page_cache.get(page_id) orelse return error.PageNotFound;
        
        // Serialize page
        const serialized = try cached_page.serialize();
        
        // Calculate offset
        const offset = page_id * @sizeOf(Page);
        
        // Write to file
        try self.file.pwriteAll(&serialized, offset);
        
        // Update file size if needed
        self.file_size = @max(self.file_size, offset + @sizeOf(Page));
    }
    
    pub fn writePages(self: *Pager, page_ids: []const PageID) !void {
        // Create a mutable copy of the page_ids slice
        const sorted_ids = try self.allocator.alloc(PageID, page_ids.len);
        defer self.allocator.free(sorted_ids);
        
        // Copy the IDs
        @memcpy(sorted_ids, page_ids);
        
        // Sort the copy for sequential access
        std.mem.sort(PageID, sorted_ids, {}, comptime std.sort.asc(PageID));
        
        // Write pages in sorted order
        for (sorted_ids) |page_id| {
            try self.writePage(page_id);
        }
    }
}; 