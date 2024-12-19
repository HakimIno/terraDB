const std = @import("std");
const enums = std.enums;
const Allocator = std.mem.Allocator;

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

pub const Parser = struct {
    lexer: *Lexer,
    current_token: Token,
    allocator: Allocator,
    
    pub fn init(lexer: *Lexer, allocator: Allocator) !Parser {
        return Parser{
            .lexer = lexer,
            .current_token = try lexer.nextToken(),
            .allocator = allocator,
        };
    }

    fn parseSelect(self: *Parser) !*ASTNode {
        try self.expect(.keyword_select);  // ตรวจสอบว่าเริ่มต้นด้วย SELECT

        const node = try ASTNode.init(self.allocator, .select_statement, "");
        errdefer node.deinit();

        // Parse columns
        while (true) {
            if (self.current_token.type == .star) {
                const star = try ASTNode.init(self.allocator, .column_ref, "*");
                try node.addChild(star);
                try self.advance();
            } else if (self.current_token.type == .identifier) {
                const column = try self.parseExpression();
                try node.addChild(column);
            } else {
                return error.UnexpectedToken;  // เพิ่มการตรวจสอบ token ที่ไม่ถูกต้อง
            }

            if (self.current_token.type != .comma) break;
            try self.advance();
        }

        // ต้องมี FROM clause
        if (self.current_token.type != .keyword_from) {
            return error.UnexpectedToken;
        }
        try self.advance();

        // ต้องมีชื่อตาราง
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
        try node.addChild(table);
        try self.advance();

        // Parse optional WHERE clause
        if (self.current_token.type == .keyword_where) {
            try self.advance();
            const condition = try self.parseExpression();
            try node.addChild(condition);
        }

        return node;
    }

    fn parseExpression(self: *Parser) ParserError!*ASTNode {
        var left = try self.parsePrimaryExpression();
        errdefer left.deinit();

        while (true) {
            const op_type = self.current_token.type;
            switch (op_type) {
                .equals, .not_equals, .greater_than, .less_than, 
                .greater_equals, .less_equals, .keyword_and, .keyword_or => {
                    const op = self.current_token.value;
                    try self.advance();
                    
                    const right = try self.parsePrimaryExpression();
                    errdefer right.deinit();
                    
                    const binary = try ASTNode.init(self.allocator, .binary_expr, op);
                    errdefer binary.deinit();
                    
                    try binary.addChild(left);
                    try binary.addChild(right);
                    left = binary;
                },
                else => break,
            }
        }

        return left;
    }

    fn parsePrimaryExpression(self: *Parser) ParserError!*ASTNode {
        switch (self.current_token.type) {
            .identifier => {
                const node = try ASTNode.init(self.allocator, .column_ref, self.current_token.value);
                try self.advance();
                return node;
            },
            .integer_literal, .float_literal, .string_literal => {
                const node = try ASTNode.init(self.allocator, .literal, self.current_token.value);
                try self.advance();
                return node;
            },
            .left_paren => {
                try self.advance();
                const expr = try self.parseExpression();
                try self.expect(.right_paren);
                return expr;
            },
            else => return error.UnexpectedToken,
        }
    }

    fn advance(self: *Parser) !void {
        self.current_token = try self.lexer.nextToken();
    }

    fn expect(self: *Parser, expected: TokenType) !void {
        if (self.current_token.type != expected) {
            return error.UnexpectedToken;
        }
        try self.advance();
    }

    fn parseInsert(self: *Parser) !*ASTNode {
        try self.expect(.keyword_insert);

        const node = try ASTNode.init(self.allocator, .insert_statement, "");
        errdefer node.deinit();

        try self.expect(.keyword_into);
        
        // Parse table name
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
        try node.addChild(table);
        try self.advance();

        // Parse column list
        try self.expect(.left_paren);
        while (true) {
            if (self.current_token.type != .identifier) {
                return error.UnexpectedToken;
            }
            const column = try ASTNode.init(self.allocator, .column_ref, self.current_token.value);
            try node.addChild(column);
            try self.advance();

            if (self.current_token.type != .comma) break;
            try self.advance();
        }
        try self.expect(.right_paren);

        // Parse VALUES
        try self.expect(.keyword_values);
        try self.expect(.left_paren);
        
        // Parse value list
        while (true) {
            const value = try self.parseExpression();
            try node.addChild(value);

            if (self.current_token.type != .comma) break;
            try self.advance();
        }
        try self.expect(.right_paren);

        return node;
    }

    fn parseUpdate(self: *Parser) !*ASTNode {
        try self.expect(.keyword_update);

        const node = try ASTNode.init(self.allocator, .update_statement, "");
        errdefer node.deinit();

        // Parse table name
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
        try node.addChild(table);
        try self.advance();

        try self.expect(.keyword_set);

        // Parse SET assignments
        while (true) {
            if (self.current_token.type != .identifier) {
                return error.UnexpectedToken;
            }
            const column = try ASTNode.init(self.allocator, .column_ref, self.current_token.value);
            try self.advance();

            try self.expect(.equals);
            
            const value = try self.parseExpression();
            const assignment = try ASTNode.init(self.allocator, .binary_expr, "=");
            try assignment.addChild(column);
            try assignment.addChild(value);
            try node.addChild(assignment);

            if (self.current_token.type != .comma) break;
            try self.advance();
        }

        // Parse optional WHERE clause
        if (self.current_token.type == .keyword_where) {
            try self.advance();
            const condition = try self.parseExpression();
            try node.addChild(condition);
        }

        return node;
    }

    fn parseDelete(self: *Parser) !*ASTNode {
        try self.expect(.keyword_delete);

        const node = try ASTNode.init(self.allocator, .delete_statement, "");
        errdefer node.deinit();

        try self.expect(.keyword_from);

        // Parse table name
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
        try node.addChild(table);
        try self.advance();

        // Parse optional WHERE clause
        if (self.current_token.type == .keyword_where) {
            try self.advance();
            const condition = try self.parseExpression();
            try node.addChild(condition);
        }

        return node;
    }

    fn parseCreate(self: *Parser) !*ASTNode {
        if (self.current_token.type == .keyword_table) {
            return self.parseCreateTable();
        } else if (self.current_token.type == .keyword_index) {
            return self.parseCreateIndex();
        }
        return error.UnexpectedToken;
    }

    fn parseCreateIndex(self: *Parser) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .create_index_statement, "");
        errdefer node.deinit();

        try self.expect(.keyword_index);

        // Parse index name
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const index_name = try ASTNode.init(self.allocator, .column_ref, self.current_token.value);
        try node.addChild(index_name);
        try self.advance();

        try self.expect(.keyword_on);

        // Parse table name
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
        try node.addChild(table);
        try self.advance();

        // Parse column list
        try self.expect(.left_paren);
        while (true) {
            if (self.current_token.type != .identifier) {
                return error.UnexpectedToken;
            }
            const column = try ASTNode.init(self.allocator, .column_ref, self.current_token.value);
            try node.addChild(column);
            try self.advance();

            if (self.current_token.type != .comma) break;
            try self.advance();
        }
        try self.expect(.right_paren);

        return node;
    }

    fn parseCreateTable(self: *Parser) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .create_table_statement, "");
        errdefer node.deinit();

        // ข้าม TABLE token
        try self.advance();

        // Parse table name
        if (self.current_token.type != .identifier) {
            return error.UnexpectedToken;
        }
        const table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
        try node.addChild(table);
        try self.advance();

        // Parse column definitions
        try self.expect(.left_paren);
        
        var first_column = true;
        while (self.current_token.type != .right_paren) {
            if (!first_column) {
                try self.expect(.comma);
            }
            first_column = false;

            // Parse column name
            if (self.current_token.type != .identifier) {
                return error.UnexpectedToken;
            }
            const column = try ASTNode.init(self.allocator, .column_def, self.current_token.value);
            errdefer column.deinit();
            try self.advance();

            // Parse column type
            if (!switch (self.current_token.type) {
                .type_int, .type_text, .type_bool, .type_float => true,
                else => false,
            }) {
                return error.UnexpectedToken;
            }
            const type_node = try ASTNode.init(self.allocator, .data_type, self.current_token.value);
            try column.addChild(type_node);
            try self.advance();

            // Parse constraints
            while (true) {
                switch (self.current_token.type) {
                    .keyword_primary => {
                        try self.advance();
                        try self.expect(.keyword_key);
                        const constraint = try ASTNode.init(self.allocator, .constraint, "PRIMARY KEY");
                        try column.addChild(constraint);
                    },
                    .keyword_not => {
                        try self.advance();
                        try self.expect(.keyword_null);
                        const constraint = try ASTNode.init(self.allocator, .constraint, "NOT NULL");
                        try column.addChild(constraint);
                    },
                    .keyword_default => {
                        try self.advance();
                        const value = try self.parseExpression();
                        errdefer value.deinit();
                        const constraint = try ASTNode.init(self.allocator, .constraint, "DEFAULT");
                        try constraint.addChild(value);
                        try column.addChild(constraint);
                    },
                    .keyword_references => {
                        try self.advance();
                        if (self.current_token.type != .identifier) {
                            return error.UnexpectedToken;
                        }
                        const ref_table = try ASTNode.init(self.allocator, .table_ref, self.current_token.value);
                        try self.advance();
                        
                        try self.expect(.left_paren);
                        if (self.current_token.type != .identifier) {
                            return error.UnexpectedToken;
                        }
                        const ref_column = try ASTNode.init(self.allocator, .column_ref, self.current_token.value);
                        try self.advance();
                        try self.expect(.right_paren);
                        
                        const constraint = try ASTNode.init(self.allocator, .constraint, "REFERENCES");
                        try constraint.addChild(ref_table);
                        try constraint.addChild(ref_column);
                        try column.addChild(constraint);
                    },
                    .comma, .right_paren => break,
                    else => return error.UnexpectedToken,
                }
            }

            try node.addChild(column);
        }
        
        try self.expect(.right_paren);
        return node;
    }

    pub fn parse(self: *Parser) !*ASTNode {
        const result = switch (self.current_token.type) {
            .keyword_select => try self.parseSelect(),
            .keyword_insert => try self.parseInsert(),
            .keyword_update => try self.parseUpdate(),
            .keyword_delete => try self.parseDelete(),
            .keyword_create => {
                try self.advance();  // ข้าม CREATE token
                const node = switch (self.current_token.type) {
                    .keyword_table => try self.parseCreateTable(),
                    .keyword_index => try self.parseCreateIndex(),
                    else => return error.UnexpectedToken,
                };
                return node;  // Return the node directly
            },
            else => return error.UnexpectedToken,
        };

        // ตรวจสอบว่าจบ statement ด้วย semicolon หรือ EOF
        if (self.current_token.type != .semicolon and self.current_token.type != .eof) {
            return error.UnexpectedToken;
        }

        return result;
    }
};

