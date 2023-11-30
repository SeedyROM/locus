//! This library aims to match the API/functionality of gettext.

const std = @import("std");
const testing = std.testing;

const Context = struct {
    allocator: std.mem.Allocator,
    locale: []const u8,

    pub fn init(allocator: std.mem.Allocator, locale: []const u8) !Context {
        return Context{
            .allocator = allocator,
            .locale = locale,
        };
    }

    pub fn deinit(_: *Context) void {}
};

const TemplateGenerator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    locale: []const u8,
    source_arena: std.heap.ArenaAllocator,
    has_errors: bool = false,

    pub fn init(allocator: std.mem.Allocator, locale: []const u8) TemplateGenerator {
        return .{
            .allocator = allocator,
            .locale = locale,
            .source_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *TemplateGenerator) void {
        self.source_arena.deinit();
    }

    pub fn generate(self: *Self, root: []const u8) !void {
        std.log.debug("Processing directory: {s}", .{root});

        // Open the root directory.
        var root_dir = try std.fs.cwd().openDir(root, .{ .iterate = true });
        defer root_dir.close();

        // Walk the directory tree and process each file.
        var dir_iterator = root_dir.iterate();
        while (try dir_iterator.next()) |entry| {
            if (entry.kind == .file) {
                const path = try self.pathFromRoot(root, entry.name);
                defer self.allocator.free(path);

                std.log.info("Processing file: {s}", .{path});
                self.processFile(path) catch {
                    std.log.err("Error processing file: {s}", .{path});
                    self.has_errors = true;
                };
            } else if (entry.kind == .directory) {
                const path = try self.pathFromRoot(root, entry.name);
                defer self.allocator.free(path);

                try self.generate(path);
            }
        }

        // Fail if there were any errors.
        if (self.has_errors) {
            return error.ParseError;
        }
    }

    // -------------------------------------------------------------------------------- //

    fn pathFromRoot(self: *Self, root: []const u8, file_path: []const u8) ![]const u8 {
        // Relative path to the file.
        // Format the relative path to the file.
        return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ root, file_path });
    }

    fn processFile(self: *Self, path: []const u8) !void {
        // Check if the file is a zig file.
        if (!isZigFile(path)) {
            std.log.debug("Skipping non-zig file: {s}", .{path});
            return;
        }

        // Get the file contents, don't need to defer because it looks like AST parse will
        // deallocate the source.
        const source = try self.readSource(path);

        // Get the AST.
        var ast = try std.zig.Ast.parse(self.allocator, source, .zig);
        defer ast.deinit(self.allocator);

        // Print the errors if there are any.
        try printAstErrors(path, source, &ast);
        // Fail if there are any errors.
        if (ast.errors.len != 0) {
            return error.ParseError;
        }
    }

    fn printAstErrors(path: []const u8, source: [:0]const u8, ast: *std.zig.Ast) !void {
        // Make sure the ast doesn't have errors.
        // This is copied from the zig codebase:
        // https://github.com/ziglang/zig/blob/master/lib/std/zig/parser_test.zig#L6175C5-L6191C6
        for (ast.errors) |parse_error| {
            const loc = ast.tokenLocation(0, parse_error.token);
            std.debug.print("{s}:{d}:{d}: error: ", .{ path, loc.line + 1, loc.column + 1 });
            try ast.renderError(parse_error, std.io.getStdErr().writer());
            std.debug.print("\n{s}\n", .{source[loc.line_start..loc.line_end]});
            {
                var i: usize = 0;
                while (i < loc.column) : (i += 1) {
                    std.debug.print(" ", .{});
                }
                std.debug.print("^", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    inline fn isZigFile(file_path: []const u8) bool {
        // Check the file extension is ".zig".
        return std.mem.endsWith(u8, file_path, ".zig");
    }

    fn readSource(self: *Self, path: []const u8) ![:0]const u8 {
        // ======================================================================================
        // Clear the file arena.
        // ======================================================================================
        // This will reuse the same memory for the file contents where the size of the arena is
        // always the size of the largest file we've processed. It will never allocate unless the
        // file is larger than the current arena size.
        //
        // All allocations using the arena will be written over when the arena is cleared. No defers are
        // needed.
        //
        // NOTE(SeedyROM): This won't work for multiple threads obviously.
        // ======================================================================================
        _ = self.source_arena.reset(.retain_capacity); // NOTE(SeedyROM): How do you handle this bool?

        // Get the allocator.
        const allocator = self.source_arena.allocator();

        // Open the file.
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Get the size of the file.
        const file_size = (try file.stat()).size;

        // Read the file contents into the buffer.
        const file_contents = try file.readToEndAllocOptions(
            allocator,
            file_size,
            null,
            @alignOf(u8),
            0,
        );

        return file_contents;
    }

    // -------------------------------------------------------------------------------- //
};

// -------------------------------------------------------------------------------- //
// API TIME
// -------------------------------------------------------------------------------- //

var context: Context = undefined;

pub fn init(allocator: std.mem.Allocator, locale: []const u8) !Context {
    context = try Context.init(allocator, locale);

    return context;
}

pub fn translate(msgid: []const u8) []const u8 {
    return msgid;
}

// -------------------------------------------------------------------------------- //

test "translator" {
    var translator = try init(testing.allocator, "en_US.UTF-8");
    defer translator.deinit();
    const __ = translate;

    try testing.expectEqualStrings(__("Hello, world!"), "Hello, world!");
}

test "template generator" {
    std.testing.log_level = .debug;
    var generator = TemplateGenerator.init(testing.allocator, "en_US.UTF-8");
    defer generator.deinit();

    try generator.generate("./test/src");
}
