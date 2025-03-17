// Make some request handling operations
const std = @import("std");
const http = std.http;
const log = std.log.scoped(.Handlers);
const builtin = @import("builtin");
//const middleware = @import("middleware.zig");

// adding global flag to track if the server should shutdown.
var should_shutdown = std.atomic.Value(bool).init(false);

// Add a function to handle the shutdown of the server.
pub fn shutdown_server(request: *http.Server.Request, query: ?[]const u8) !void {
    // expressly ignore queries
    _ = query;

    var extra_headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/plain" },
    };

    std.debug.print("Shutdown request received. Server will gracefully exit.", .{});
    should_shutdown.store(true, .seq_cst);
    try request.respond("Server shutting down...\n", .{ .extra_headers = &extra_headers });
}

// Adding listener for if we should have shutdown or not.
pub fn check_shutdown() bool {
    return should_shutdown.load(.seq_cst);
}

fn process_params(query: ?[]const u8) !std.StringHashMap([]const u8) {
    const allocator = std.heap.page_allocator;
    var params = std.StringHashMap([]const u8).init(allocator);
    if (query) |q| {
        const sanatized_q = if (q[0] == '?') q[1..] else q;
        var it = std.mem.split(u8, sanatized_q, "&");
        while (it.next()) |pair| {
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq_index| {
                const key = pair[0..eq_index];
                const value = pair[eq_index + 1 ..];
                try params.put(key, value);
            }
        }
    }

    return params;
}

pub fn refresh_oauth(request: *http.Server.Request, query: ?[]const u8) !void {
    var params = try process_params(query);
    defer params.deinit();
    var extra_headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/plain" },
    };

    const token: []const u8 = params.get("refreshToken") orelse {
        return request.respond("Missing parameter 'refreshToken'\n", .{ .status = .bad_request });
    };
    const verifier: []const u8 = params.get("verifier") orelse {
        return request.respond("Missing parameter 'verifier'\n", .{ .status = .bad_request });
    };
    std.debug.print("OAUTH Refresh triggered.... received: Verifier: {s}, token: {s}\n", .{ verifier, token });
    try request.respond("Request received....\n", .{ .extra_headers = &extra_headers, .status = .accepted });
}

pub fn srvLandPage(request: *http.Server.Request) !void {
    var extra_headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/html" },
    };
    const html_content =
        "<!DOCTYPE html>" ++ "<html lang=\"en\">" ++ "<head>" ++ "<meta charset=\"UTF-8\">" ++ "<title>EVE Online OAuth Confirmation</title>" ++ "<link rel=\"icon\" type=\"image/x-icon\" href=\"/favicon.ico\">" ++ "<style>body { background-color: #0f0f0f; color: #ffffff; font-family: Arial, sans-serif; text-align: center; padding: 50px; }" ++ ".container { max-width: 600px; margin: auto; background: rgba(255, 255, 255, 0.1); padding: 20px; border-radius: 10px; box-shadow: 0 0 10px rgba(255, 255, 255, 0.2); }" ++ "h1 { color: #ffcc00; }</style>" ++ "</head>" ++ "<body><div class=\"container\"><h1>Authentication Successful</h1><p>You have successfully authenticated via EVE Online.</p>" ++ "<p>You may now return to the application.</p></div></body></html>";

    try request.respond(html_content, .{
        .status = .ok,
        .extra_headers = &extra_headers,
    });
    //const allocator = std.heap.page_allocator;
    //const html_file = try std.fs.cwd().openFile("../content/landing.html", .{});
    //defer html_file.close();
    //const file_stat = try html_file.stat();
    //const html_content = try html_file.readToEndAlloc(allocator, file_stat.size);
    //defer allocator.free(html_content);
    //try request.respond(html_content, .{ .status = .ok });
}

//Make our oauth_callback processor to gather the code and state parameters
pub fn oauth_callback(request: *http.Server.Request, query: ?[]const u8) !void {
    var params = try process_params(query);
    defer params.deinit();
    //var extra_headers = [_]http.Header{
    //    .{ .name = "Content-Type", .value = "text/plain" },
    //};

    const code: []const u8 = params.get("code") orelse {
        return request.respond("Missing parameter 'code'\n", .{ .status = .bad_request });
    };
    const state: []const u8 = params.get("state") orelse {
        return request.respond("Missing parameter 'state'\n", .{ .status = .bad_request });
    };
    std.debug.print("OAUTH Callback request received: Code: {s}, state: {s}\n", .{ code, state });
    try srvLandPage(request);
}

fn auth_fail_scrub(request: *http.Server.Request, oauth_url: []const u8) !void {
    var extra_headers = [_]http.Header{
        .{ .name = "Content-TYpe", .value = "text/plain" },
    };
    const failure_msg: []const u8 =
        \\ Authentication failed due to problems with your system's inability to follow simple instructions.
        \\ This is not a development issue. This is your issue.
        \\ Maybe install a real OS (ARCH mentioned) before attempting custom API integrations?
        \\ Alternatively, learn some troubleshooting skills.
        \\ Until then, copy-paste has worked since 1995; maybe give that a shot:
        \\ {s}
        \\
    ;

    const responseText = try std.fmt.allocPrint(std.heap.page_allocator, failure_msg, .{oauth_url});

    try request.respond(responseText, .{
        .status = .internal_server_error,
        .extra_headers = &extra_headers,
    });
}

pub fn initiate_oauthrequest(request: *http.Server.Request, query: ?[]const u8) !void {
    const allocator = std.heap.page_allocator;

    // Parse query parameters
    var params = try process_params(query);
    defer params.deinit();

    var extra_headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "text/plain" },
    };

    const clientId = params.get("clientId") orelse {
        return request.respond("Missing parameter 'clientId'\n", .{ .status = .bad_request });
    };
    const redirectUri = params.get("redirectUri") orelse {
        return request.respond("Missing parameter 'redirectUri'\n", .{ .status = .bad_request });
    };
    const state = params.get("state") orelse {
        return request.respond("Missing parameter 'state'\n", .{ .status = .bad_request });
    };
    const codeChallenge = params.get("codeChallenge") orelse {
        return request.respond("Missing parameter 'codeChallenge'\n", .{ .status = .bad_request });
    };

    // Define scopes properly as a string
    const scopes = "publicData esi-location.read_location.v1 esi-wallet.read_character_wallet.v1 esi-search.search_structures.v1 esi-universe.read_structures.v1 esi-assets.read_assets.v1 esi-ui.write_waypoint.v1 esi-industry.read_character_jobs.v1 esi-markets.read_character_orders.v1 esi-characters.read_blueprints.v1 esi-contracts.read_character_contracts.v1 esi-industry.read_character_mining.v1 esi-characterstats.read.v1";

    // Construct the OAuth URL using `std.fmt.allocPrint`
    const oauth_url = try std.fmt.allocPrint(allocator, "https://login.eveonline.com/v2/oauth/authorize?response_type=code&client_id={s}&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{ clientId, redirectUri, scopes, codeChallenge, state });

    const response_msg: []const u8 = "Congratulations, you have started the Authentication workflow.\n" ++ "Please continue to sign in using your browser.\n";
    // Send response with the login URL

    var cmd: []const u8 = undefined;
    var args: []const []const u8 = undefined;
    switch (builtin.os.tag) {
        .windows => {
            cmd = "cmd";
            args = &[_][]const u8{ "cmd", "/c", "start", oauth_url };
        },
        .linux => {
            cmd = "xdg-open";
            args = &[_][]const u8{ "xdg-open", oauth_url };
        },
        .macos => {
            cmd = "open";
            args = &[_][]const u8{ "open", oauth_url };
        },
        else => {
            error.UnsupportedOS;
        },
    }

    // Spawn the child process using `std.process.Child`
    var child = std.process.Child.init(args, allocator);
    //child.stdin_behavior = .Close;
    //child.stdout_behavior = .Ignore;
    //child.stderr_behavior = .Ignore;

    child.spawn() catch |err| {
        log.err("Failed to open browser: {}", .{err});
        try auth_fail_scrub(request, oauth_url);
        defer allocator.free(oauth_url); // Free memory after use
        return;
    };
    defer allocator.free(oauth_url); // Free memory after use
    return request.respond(response_msg, .{ .status = .ok, .extra_headers = &extra_headers });
}
