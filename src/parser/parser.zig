const std = @import("std");
const enums = std.enums;
const Allocator = std.mem.Allocator;
const lexer = @import("lexer.zig");
pub const FastLexer = lexer.FastLexer;

pub const TokenType = enum {
    // Keywords
    keyword_select,
    keyword_from,
    keyword_where,
    keyword_insert,
    keyword_into,
    keyword_values,
    keyword_update,
    keyword_set,
    keyword_delete,
    keyword_create,
    keyword_table,
    keyword_index,
    keyword_primary,
    keyword_key,
    keyword_not,
    keyword_null,
    keyword_default,
    keyword_references,
    keyword_on,
    keyword_and,
    keyword_or,

    // Data types
    type_int,
    type_text,
    type_bool,
    type_float,

    // Operators
    equals,
    not_equals,
    greater_than,
    less_than,
    greater_equals,
    less_equals,

    // Punctuation
    left_paren,
    right_paren,
    comma,
    semicolon,
    star,

    // Values
    identifier,
    integer_literal,
    float_literal,
    string_literal,

    // Special
    eof,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
    column: usize,
    
    pub fn init(token_type: TokenType, value: []const u8, line: usize, column: usize) Token {
        return .{
            .type = token_type,
            .value = value,
            .line = line,
            .column = column,
        };
    }
};

pub const LexerError = error{
    InvalidCharacter,
    UnterminatedString,
    InvalidOperator,
} || std.mem.Allocator.Error;

pub const Lexer = struct {
    input: []const u8,
    position: usize,
    line: usize,
    column: usize,
    allocator: Allocator,
    keywords: std.StringHashMap(TokenType),
    peek_token: ?Token,
    has_peek: bool,
    
    pub fn init(input: []const u8, allocator: Allocator) Lexer {
        var keywords = std.StringHashMap(TokenType).init(allocator);
        
        // Add keywords
        keywords.put("SELECT", .keyword_select) catch unreachable;
        keywords.put("FROM", .keyword_from) catch unreachable;
        keywords.put("WHERE", .keyword_where) catch unreachable;
        keywords.put("INSERT", .keyword_insert) catch unreachable;
        keywords.put("INTO", .keyword_into) catch unreachable;
        keywords.put("VALUES", .keyword_values) catch unreachable;
        keywords.put("UPDATE", .keyword_update) catch unreachable;
        keywords.put("SET", .keyword_set) catch unreachable;
        keywords.put("DELETE", .keyword_delete) catch unreachable;
        keywords.put("CREATE", .keyword_create) catch unreachable;
        keywords.put("TABLE", .keyword_table) catch unreachable;
        keywords.put("INDEX", .keyword_index) catch unreachable;
        keywords.put("PRIMARY", .keyword_primary) catch unreachable;
        keywords.put("KEY", .keyword_key) catch unreachable;
        keywords.put("NOT", .keyword_not) catch unreachable;
        keywords.put("NULL", .keyword_null) catch unreachable;
        keywords.put("DEFAULT", .keyword_default) catch unreachable;
        keywords.put("REFERENCES", .keyword_references) catch unreachable;
        keywords.put("ON", .keyword_on) catch unreachable;
        keywords.put("AND", .keyword_and) catch unreachable;
        keywords.put("OR", .keyword_or) catch unreachable;

        // Add data types
        keywords.put("INT", .type_int) catch unreachable;
        keywords.put("TEXT", .type_text) catch unreachable;
        keywords.put("BOOL", .type_bool) catch unreachable;
        keywords.put("FLOAT", .type_float) catch unreachable;
        
        return .{
            .input = input,
            .position = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
            .keywords = keywords,
            .peek_token = null,
            .has_peek = false,
        };
    }
    
    fn isOperatorStart(char: u8) bool {
        return switch (char) {
            '=', '>', '<', '!', '+', '-', '*', '/' => true,
            else => false,
        };
    }
    
    pub fn nextToken(self: *Lexer) LexerError!Token {
        if (self.has_peek) {
            self.has_peek = false;
            return self.peek_token.?;
        }
        
        self.skipWhitespace();
        
        if (self.position >= self.input.len) {
            return Token.init(.eof, "", self.line, self.column);
        }
        
        const char = self.input[self.position];
        
        // Handle single-character tokens
        const single_char_token: ?TokenType = switch (char) {
            '(' => .left_paren,
            ')' => .right_paren,
            ',' => .comma,
            ';' => .semicolon,
            '*' => .star,
            else => null,
        };
        
        if (single_char_token) |token_type| {
            const token = Token.init(token_type, self.input[self.position..self.position+1], self.line, self.column);
            self.position += 1;
            self.column += 1;
            return token;
        }
        
        // Handle operators
        if (isOperatorStart(char)) {
            return self.readOperator();
        }
        
        // Handle string literals
        if (char == '\'') {
            return self.readString();
        }
        
        // Handle numbers
        if (std.ascii.isDigit(char)) {
            return self.readNumber();
        }
        
        // Handle identifiers and keywords
        if (std.ascii.isAlphabetic(char)) {
            return self.readIdentifier();
        }
        
        return error.InvalidCharacter;
    }
    
    fn skipWhitespace(self: *Lexer) void {
        while (self.position < self.input.len) {
            const char = self.input[self.position];
            switch (char) {
                ' ', '\t' => {
                    self.position += 1;
                    self.column += 1;
                },
                '\n' => {
                    self.position += 1;
                    self.line += 1;
                    self.column = 1;
                },
                '\r' => {
                    self.position += 1;
                },
                else => break,
            }
        }
    }
    
    fn readIdentifier(self: *Lexer) LexerError!Token {
        const start = self.position;
        const start_column = self.column;
        
        while (self.position < self.input.len) : (self.position += 1) {
            const c = self.input[self.position];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
        }
        
        const identifier = self.input[start..self.position];
        
        if (self.keywords.get(identifier)) |keyword_type| {
            return Token.init(keyword_type, identifier, self.line, start_column);
        }
        
        return Token.init(.identifier, identifier, self.line, start_column);
    }
    
    fn readString(self: *Lexer) LexerError!Token {
        const start_column = self.column;
        const start_pos = self.position;  // Keep track of starting position including quote
        
        // Skip opening quote
        self.position += 1;
        self.column += 1;
        
        var found_closing_quote = false;
        
        while (self.position < self.input.len) {
            const char = self.input[self.position];
            if (char == '\'') {
                found_closing_quote = true;
                self.position += 1;  // Move past closing quote
                self.column += 1;
                break;
            }
            if (char == '\n') {
                return error.UnterminatedString;
            }
            self.position += 1;
            self.column += 1;
        }
        
        if (!found_closing_quote) {
            return error.UnterminatedString;
        }
        
        // Include quotes in the token value
        return Token.init(
            .string_literal,
            self.input[start_pos..self.position],  // Include both quotes in the value
            self.line,
            start_column
        );
    }
    
    fn readNumber(self: *Lexer) LexerError!Token {
        const start = self.position;
        const start_column = self.column;
        var has_decimal = false;
        
        while (self.position < self.input.len) {
            const char = self.input[self.position];
            if (char == '.') {
                if (has_decimal) break;
                has_decimal = true;
            } else if (!std.ascii.isDigit(char)) {
                break;
            }
            self.position += 1;
            self.column += 1;
        }
        
        const token_type: TokenType = if (has_decimal) .float_literal else .integer_literal;
        return Token.init(token_type, self.input[start..self.position], self.line, start_column);
    }
    
    fn readOperator(self: *Lexer) LexerError!Token {
        const start = self.position;
        const start_column = self.column;
        
        const first_char = self.input[self.position];
        self.position += 1;
        self.column += 1;
        
        // Check for two-character operators
        if (self.position < self.input.len) {
            const second_char = self.input[self.position];
            const two_char_op: ?TokenType = switch (first_char) {
                '=' => if (second_char == '=') .equals else null,
                '!' => if (second_char == '=') .not_equals else null,
                '>' => if (second_char == '=') .greater_equals else null,
                '<' => if (second_char == '=') .less_equals else null,
                else => null,
            };
            
            if (two_char_op) |token_type| {
                self.position += 1;
                self.column += 1;
                return Token.init(token_type, self.input[start..self.position], self.line, start_column);
            }
        }
        
        // Single-character operators
        const single_char_op: TokenType = switch (first_char) {
            '>' => .greater_than,
            '<' => .less_than,
            '=' => .equals,
            else => return error.InvalidOperator,
        };
        
        return Token.init(single_char_op, self.input[start..self.position], self.line, start_column);
    }
    
    pub fn peekToken(self: *Lexer) LexerError!Token {
        if (self.has_peek) {
            return self.peek_token.?;
        }

        // บันทึกตำแหน่งปัจจุบัน
        const saved_pos = self.position;
        const saved_line = self.line;
        const saved_column = self.column;

        // อ่าน token ถัดไป
        const next_token = try self.nextToken();

        // เก็บ token ไว้
        self.peek_token = next_token;
        self.has_peek = true;

        // คืนค่าตำแหน่งกลับไปที่เดิม
        self.position = saved_pos;
        self.line = saved_line;
        self.column = saved_column;

        return next_token;
    }
};

pub const ASTNodeType = enum {
    select_statement,
    insert_statement,
    update_statement,
    delete_statement,
    create_table_statement,
    create_index_statement,
    column_ref,
    table_ref,
    binary_expr,
    literal,
    function_call,
    join_expr,
    column_def,
    data_type,
    constraint,
    identifier,
    create_statement,
    unknown_statement,
};

pub const ASTNode = struct {
    // ใช้ small buffer optimization
    const SmallBuffer = struct {
        data: [4]*ASTNode,
        len: usize,
    };
    
    allocator: Allocator,
    type: ASTNodeType,
    value: []const u8,
    children: union {
        small: SmallBuffer,
        large: std.ArrayList(*ASTNode),
    },
    is_small: bool,
    
    pub fn init(allocator: Allocator, node_type: ASTNodeType, value: []const u8) !*ASTNode {
        const node = try allocator.create(ASTNode);
        node.* = .{
            .allocator = allocator,
            .type = node_type,
            .value = value,
            .children = .{ .small = .{ .data = undefined, .len = 0 } },
            .is_small = true,
        };
        return node;
    }
    
    pub fn deinit(self: *ASTNode) void {
        if (!self.is_small) {
            for (self.children.large.items) |child| {
                child.deinit();
                self.allocator.destroy(child);
            }
            self.children.large.deinit();
        } else {
            for (self.children.small.data[0..self.children.small.len]) |child| {
                child.deinit();
                self.allocator.destroy(child);
            }
        }
    }
    
    pub fn addChild(self: *ASTNode, child: *ASTNode) !void {
        if (self.is_small) {
            if (self.children.small.len < 4) {
                self.children.small.data[self.children.small.len] = child;
                self.children.small.len += 1;
                return;
            }
            // ถ้าเต็ม small buffer ให้ย้ายไป large buffer
            try self.convertToLarge();
        }
        try self.children.large.append(child);
    }
    
    fn convertToLarge(self: *ASTNode) !void {
        var large = std.ArrayList(*ASTNode).init(self.allocator);
        try large.ensureTotalCapacity(8); // Pre-allocate some space
        
        // Copy existing items from small buffer
        for (self.children.small.data[0..self.children.small.len]) |child| {
            try large.append(child);
        }
        self.children = .{ .large = large };
        self.is_small = false;
    }
    
    pub fn getChildren(self: *const ASTNode) []const *ASTNode {
        return if (self.is_small)
            self.children.small.data[0..self.children.small.len]
        else
            self.children.large.items;
    }
};

pub const ParserError = error{
    UnexpectedToken,
} || LexerError || std.mem.Allocator.Error;

// Custom allocator optimized for parser
const ParserAllocator = struct {
    const BLOCK_SIZE = 4096;
    const MAX_BLOCKS = 32;

    blocks: [MAX_BLOCKS][]u8,
    block_count: usize,
    current_offset: usize,
    base_allocator: Allocator,

    fn init(base_allocator: Allocator) !ParserAllocator {
        var self = ParserAllocator{
            .blocks = undefined,
            .block_count = 0,
            .current_offset = BLOCK_SIZE,
            .base_allocator = base_allocator,
        };
        try self.addBlock();
        return self;
    }

    fn addBlock(self: *ParserAllocator) !void {
        if (self.block_count >= MAX_BLOCKS) return error.OutOfMemory;
        const block = try self.base_allocator.alloc(u8, BLOCK_SIZE);
        self.blocks[self.block_count] = block;
        self.block_count += 1;
        self.current_offset = 0;
    }

    fn allocBlock(self: *ParserAllocator, size: usize) ![]u8 {
        if (size > BLOCK_SIZE) return error.OutOfMemory;
        if (self.current_offset + size > BLOCK_SIZE) {
            try self.addBlock();
        }
        const result = self.blocks[self.block_count - 1][self.current_offset..self.current_offset + size];
        self.current_offset += size;
        return result;
    }

    fn deinit(self: *ParserAllocator) void {
        for (self.blocks[0..self.block_count]) |block| {
            self.base_allocator.free(block);
        }
    }

    pub fn allocator(self: *ParserAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = allocFn,
                .resize = resizeFn,
                .free = freeFn,
            },
        };
    }

    fn allocFn(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ptr_align;
        _ = ret_addr;
        const self = @as(*ParserAllocator, @alignCast(@ptrCast(ctx)));
        if (self.allocBlock(len)) |result| {
            return result.ptr;
        } else |_| {
            return null;
        }
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;  // We don't support resizing
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // No-op - memory is freed when ParserAllocator is deinitialized
    }
};

// Add this enum definition before FastParser
pub const StatementType = enum {
    select,
    insert,
    update,
    delete,
    create,
    unknown,
};

// Optimized parser with custom allocator
pub const FastParser = struct {
    lexer_instance: *FastLexer,
    current_token: Token,
    allocator: ParserAllocator,
    
    pub fn init(lexer_in: *FastLexer, base_allocator: Allocator) !FastParser {
        return FastParser{
            .lexer_instance = lexer_in,
            .current_token = (try lexer_in.nextToken()).toParserToken(),
            .allocator = try ParserAllocator.init(base_allocator),
        };
    }

    // Add deinit function
    pub fn deinit(self: *FastParser) void {
        self.allocator.deinit();
    }

    // เพิ่มฟังก์ชันสำหรับ parse แต่ละประเภท
    fn parseSelect(self: *FastParser) !*ASTNode {
        const node = try ASTNode.init(self.allocator.allocator(), .select_statement, "");
        // TODO: Implement SELECT parsing
        return node;
    }

    fn parseInsert(self: *FastParser) !*ASTNode {
        const node = try ASTNode.init(self.allocator.allocator(), .insert_statement, "");
        // TODO: Implement INSERT parsing
        return node;
    }

    fn parseUpdate(self: *FastParser) !*ASTNode {
        const node = try ASTNode.init(self.allocator.allocator(), .update_statement, "");
        // TODO: Implement UPDATE parsing
        return node;
    }

    fn parseDelete(self: *FastParser) !*ASTNode {
        const node = try ASTNode.init(self.allocator.allocator(), .delete_statement, "");
        // TODO: Implement DELETE parsing
        return node;
    }

    fn parseCreate(self: *FastParser) !*ASTNode {
        const node = try ASTNode.init(self.allocator.allocator(), .create_statement, "");
        // TODO: Implement CREATE parsing
        return node;
    }

    fn parseUnknown(self: *FastParser) !*ASTNode {
        const node = try ASTNode.init(self.allocator.allocator(), .unknown_statement, "");
        // TODO: Implement generic parsing
        return node;
    }

    // Parse with statement type hints for better branch prediction
    pub fn parse(self: *FastParser, hint: StatementType) !*ASTNode {
        return switch (hint) {
            .select => self.parseSelect(),
            .insert => self.parseInsert(),
            .update => self.parseUpdate(),
            .delete => self.parseDelete(),
            .create => self.parseCreate(),
            .unknown => self.parseUnknown(),
        };
    }
};

