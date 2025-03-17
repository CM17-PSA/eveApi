//Import standard
const std = @import("std");
const http = std.http;
const net = std.net;
const handlers = @import("handlers.zig");

pub fn ServerStart(server: *net.Server) void {
    while (true) {
        if (handlers.check_shutdown()) {
            std.debug.print("Shutting down server gracefully.\n", .{});
            break;
        }
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
    std.debug.print("Handling request for {any} {s}\n", .{ request.head.method, request.head.target });
    // define pathing and query definitions
    var path: []const u8 = request.head.target;
    var query: ?[]const u8 = null;
    var extra_headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/plain" },
    };

    // parse the path and query
    if (std.mem.indexOfScalar(u8, path, '?')) |q_index| {
        query = path[q_index..];
        path = path[0..q_index];
    }

    //confirm definitions of handled pathings
    switch (request.head.method) {
        http.Method.GET => {
            if (std.mem.eql(u8, path, "/auth/initiate")) {
                return try handlers.initiate_oauthrequest(request, query);
            } else if (std.mem.eql(u8, path, "/indy_callback")) {
                return try handlers.oauth_callback(request, query);
            } else if (std.mem.eql(u8, path, "/shutdown")) {
                return try handlers.shutdown_server(request, query);
            }
        },
        http.Method.POST => {
            if (std.mem.eql(u8, path, "/auth/refresh")) {
                return try handlers.refresh_oauth(request, query);
            }
        },
        else => {
            try request.respond("Method not allowed\n", .{
                .extra_headers = &extra_headers,
                .status = .bad_request,
            });
        },
    }
    //404 it
    try request.respond("Not Found\n", .{
        .extra_headers = &extra_headers,
        .status = .not_found,
    });
}
