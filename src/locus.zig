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

var context: Context = undefined;

pub fn init(allocator: std.mem.Allocator, locale: []const u8) !Context {
    context = try Context.init(allocator, locale);

    return context;
}

pub fn translate(msgid: []const u8) []const u8 {
    return msgid;
}

const TemplateGenerator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    locale: []const u8,
    file_arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, locale: []const u8) TemplateGenerator {
        return .{
            .allocator = allocator,
            .locale = locale,
            .file_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *TemplateGenerator) void {
        self.file_arena.deinit();
    }

    pub fn generate(self: *Self, root: []const u8) !void {
        std.log.info("Processing directory: {s}", .{root});

        // Open the root directory.
        var root_dir = try std.fs.cwd().openDir(root, .{ .iterate = true });
        defer root_dir.close();

        // Walk the directory tree.
        var dir_iterator = root_dir.iterate();
        while (try dir_iterator.next()) |entry| {
            if (entry.kind == .file) {
                const path = try self.pathFromRoot(root, entry.name);
                try self.processFile(path);
            } else if (entry.kind == .directory) {
                const path = try self.pathFromRoot(root, entry.name);
                try self.generate(path);
            }
        }
    }

    // -------------------------------------------------------------------------------- //

    fn pathFromRoot(self: *Self, root: []const u8, file_path: []const u8) ![]const u8 {
        // Relative path to the file.
        // Format the relative path to the file.
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ root, file_path });
        std.log.info("Processing file: {s}\n", .{path});

        return path;
    }

    fn processFile(self: *Self, path: []const u8) !void {
        defer self.allocator.free(path);

        // Check if the file is a zig file.
        if (!isZigFile(path)) {
            std.log.debug("Skipping non-zig file: {s}\n", .{path});
            return;
        }

        // Get the file contents.
        const file_contents = try self.getFileContents(path);

        // Print the file for now
        std.debug.print("{s}\n", .{file_contents});
    }

    fn isZigFile(file_path: []const u8) bool {
        // Check the file extension is ".zig".
        return std.mem.endsWith(u8, file_path, ".zig");
    }

    fn getFileContents(self: *Self, path: []const u8) ![]const u8 {
        // ======================================================================================
        // Clear the file arena.
        // ======================================================================================
        // This will reuse the same memory for the file contents where the size of the arena is
        // always the size of the largest file we've processed. It will never allocate unless the
        // file is larger than the current arena size.
        //
        // All allocations using the arena will be written over when the arena is cleared. No defers are
        // needed.
        // ======================================================================================
        _ = self.file_arena.reset(.retain_capacity); // NOTE(SeedyROM): How do you handle this bool?

        // Get the allocator.
        const allocator = self.file_arena.allocator();

        // Open the file.
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // Get the size of the file.
        const file_size = (try file.stat()).size;

        // Allocate a buffer for the file contents.
        const file_contents = try allocator.alloc(u8, file_size);

        // Read the file contents into the buffer.
        const bytes_read = try file.readAll(file_contents);

        // Assert we read the entire file.
        if (bytes_read != file_size) {
            std.log.err("Failed to read entire file: {s}\n", .{path});
            return error.FileReadFailed;
        }

        return file_contents;
    }

    // -------------------------------------------------------------------------------- //
};

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
