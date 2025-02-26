// Creating an HTTP Server rolled from scratch
// Credit to blog.orhun.dev/zig-bits-04 for baseline guidance and walkthrough
const std = @import("std");
const log = std.log.scoped(.server);
const server_addr = "127.0.0.1";
const server_port = 8000;
const serverRunTime = @import("server.zig");
// Import our http definitions from std
pub fn main() !void {
    const addr = std.net.Address.parseIp4(server_addr, server_port) catch |err| {
        std.debug.print("An error occurred while resolving the IP address: {}\n", .{err});
        return;
    };
    var server = try addr.listen(.{});
    serverRunTime.ServerStart(&server);
}
