const std = @import("std");
const net = std.net;
const os = std.os;
const mem = std.mem;
const Allocator = std.mem.Allocator;

// คำสั่งต่างๆ ใน protocol
pub const Command = enum(u8) {
    Query = 'Q',
    Execute = 'E',
    Parse = 'P',
    Bind = 'B',
    Describe = 'D',
    Sync = 'S',
    Terminate = 'X',
};

// โครงสร้างของ connection
pub const Connection = struct {
    stream: net.Stream,
    buffer: []u8,
    allocator: Allocator,
    is_connected: bool,

    const Self = @This();
    const buffer_size = 8192;

    // สร้าง connection ใหม่
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .stream = undefined,
            .buffer = try allocator.alloc(u8, buffer_size),
            .allocator = allocator,
            .is_connected = false,
        };
        return self;
    }

    // ทำลาย connection
    pub fn deinit(self: *Self) void {
        if (self.is_connected) {
            self.stream.close();
        }
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    // เชื่อมต่อไปยัง server
    pub fn connect(self: *Self, host: []const u8, port: u16) !void {
        if (self.is_connected) return error.AlreadyConnected;

        const address = try net.Address.parseIp(host, port);
        self.stream = try net.tcpConnectToAddress(address);
        self.is_connected = true;

        try self.sendStartupMessage();
        try self.handleAuthentication();
    }

    // ส่ง startup message
    fn sendStartupMessage(self: *Self) !void {
        const protocol_version = 196608; // PostgreSQL protocol version 3.0
        const user = "postgres";
        const database = "postgres";

        var msg = std.ArrayList(u8).init(self.allocator);
        defer msg.deinit();

        // Protocol version
        try msg.writer().writeIntBig(i32, protocol_version);
        
        // Parameters
        try msg.writer().writeAll("user\x00");
        try msg.writer().writeAll(user);
        try msg.writer().writeByte(0);
        try msg.writer().writeAll("database\x00");
        try msg.writer().writeAll(database);
        try msg.writer().writeByte(0);
        try msg.writer().writeByte(0);

        try self.sendMessage('0', msg.items);
    }

    // ส่งคำสั่ง query
    pub fn query(self: *Self, sql: []const u8) !void {
        if (!self.is_connected) return error.NotConnected;

        try self.sendMessage(Command.Query, sql);
        try self.readResponse();
    }

    // ส่ง message ไปยัง server
    fn sendMessage(self: *Self, type_byte: u8, message: []const u8) !void {
        var msg = std.ArrayList(u8).init(self.allocator);
        defer msg.deinit();

        // Message type
        try msg.append(type_byte);

        // Message length (including length itself but not type byte)
        const len = @as(i32, @intCast(message.len + 4));
        try msg.writer().writeIntBig(i32, len);

        // Message content
        try msg.appendSlice(message);

        _ = try self.stream.write(msg.items);
    }

    // อ่าน response จาก server
    fn readResponse(self: *Self) !void {
        while (true) {
            const type_byte = try self.stream.reader().readByte();
            const length = try self.stream.reader().readIntBig(i32);
            const message_length = @as(usize, @intCast(length - 4));

            if (message_length > self.buffer.len) {
                return error.MessageTooLarge;
            }

            const read_amount = try self.stream.read(self.buffer[0..message_length]);
            if (read_amount != message_length) {
                return error.UnexpectedEOF;
            }

            switch (type_byte) {
                'Z' => break, // ReadyForQuery
                'E' => return error.ErrorResponse,
                else => {}, // Handle other response types
            }
        }
    }

    // จัดการ authentication
    fn handleAuthentication(self: *Self) !void {
        const auth_type = try self.stream.reader().readIntBig(i32);
        switch (auth_type) {
            0 => {}, // OK
            5 => try self.handleMD5Authentication(),
            else => return error.UnsupportedAuthMethod,
        }
    }

    // จัดการ MD5 authentication
    fn handleMD5Authentication(self: *Self) !void {
        var salt: [4]u8 = undefined;
        _ = try self.stream.read(&salt);

        // TODO: Implement MD5 authentication
        @panic("MD5 authentication not implemented");
    }

    // ปิดการเชื่อมต่อ
    pub fn disconnect(self: *Self) !void {
        if (!self.is_connected) return;

        try self.sendMessage(Command.Terminate, "");
        self.stream.close();
        self.is_connected = false;
    }
};

// Pool ของ connections
pub const ConnectionPool = struct {
    connections: std.ArrayList(*Connection),
    allocator: Allocator,
    max_connections: usize,

    const Pool = @This();

    // สร้าง connection pool
    pub fn init(allocator: Allocator, max_connections: usize) !*Pool {
        const pool = try allocator.create(Pool);
        pool.* = .{
            .connections = std.ArrayList(*Connection).init(allocator),
            .allocator = allocator,
            .max_connections = max_connections,
        };
        return pool;
    }

    // ทำลาย connection pool
    pub fn deinit(self: *Pool) void {
        for (self.connections.items) |conn| {
            conn.deinit();
        }
        self.connections.deinit();
        self.allocator.destroy(self);
    }

    // ขอ connection จาก pool
    pub fn acquire(self: *Pool) !*Connection {
        if (self.connections.items.len < self.max_connections) {
            const conn = try Connection.init(self.allocator);
            try self.connections.append(conn);
            return conn;
        }
        return error.NoAvailableConnections;
    }

    // คืน connection กลับ pool
    pub fn release(self: *Pool, conn: *Connection) void {
        _ = self;
        _ = conn;
        // TODO: Implement connection reuse
    }
};

// ตัวอย่างการใช้งาน
pub fn example() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // สร้าง connection pool
    const pool = try ConnectionPool.init(allocator, 10);
    defer pool.deinit();

    // ขอ connection และใช้งาน
    const conn = try pool.acquire();
    try conn.connect("localhost", 5432);
    defer conn.disconnect() catch {};

    // ส่งคำสั่ง query
    try conn.query("SELECT * FROM users");
}