//Import standard
const std = @import("std");
const http = std.http;
const net = std.net;

pub fn ServerStart(server: *net.Server) void {
    while (true) {
        var connection = server.accept() catch |err| {
            std.debug.print("Connection to client interrupted: {}\n", .{err});
            continue;
        };
        defer connection.stream.close();
        var read_buffer: [1024]u8 = undefined;
        var http_server = http.Server.init(connection, &read_buffer);
        var request = http_server.receiveHead() catch |err| {
            std.debug.print("Could not read head: {}\n", .{err});
            continue;
        };
        handle_request(&request) catch |err| {
            std.debug.print("Could not handle request: {}", .{err});
            continue;
        };
    }
}

pub fn handle_request(request: *http.Server.Request) !void {
    std.debug.print("Handling request for {s}\n", .{request.head.target});
    try request.respond("Hello http!\n", .{});
}
