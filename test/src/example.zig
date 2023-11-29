const std = @import("std");

const locus = @import("locus");
const __ = locus.translate;

const gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() void {
    locus.init(allocator, "en_US.UTF-8");

    std.debug.print(__("Hello, world!\n"), .{});
}
