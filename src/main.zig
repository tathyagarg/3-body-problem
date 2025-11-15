const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const config = @import("config");

const style = @embedFile("style");

// TODO: Make RADIUS dynamic
const RADIUS = 2.5;

const SCREEN_WIDTH: i32 = config.screen_width;
const SCREEN_HEIGHT: i32 = config.screen_height;

const TARGET_FPS = 60;

const CAMERA_SPEED = 3;
const TRAIL_LENGTH = 100;
const TOTAL_EDITABLE_UI = 3;

// i hate that this is hardcoded but im not about to write a dynamic ui system rn
const POSITIONS: [3]rl.Rectangle = .{
    .{ .x = SCREEN_WIDTH - 230, .y = 320, .width = 50, .height = 30 },
    .{ .x = SCREEN_WIDTH - 170, .y = 320, .width = 50, .height = 30 },
    .{ .x = SCREEN_WIDTH - 110, .y = 320, .width = 50, .height = 30 },
};

const controls_pos = enum(usize) {
    VISIBLE,
    HIDDEN,
    ADDING_BODY,
};

const Body = struct {
    position: rl.Vector3,
    velocity: rl.Vector3,

    mass: f32,

    // i like blue
    color: rl.Color = .blue,

    // velocity.length()
    // used for velocity bar display
    raw_vel: f32 = 0.0,

    trail: [TRAIL_LENGTH]rl.Vector3 = undefined,
    trail_index: usize = 0,

    pub fn init(position: rl.Vector3, velocity: rl.Vector3, mass: f32, color: rl.Color) Body {
        var body = Body{
            .position = position,
            .velocity = velocity,
            .mass = mass,
            .color = color,
        };

        body.raw_vel = body.velocity.length();
        body.trail = [_]rl.Vector3{body.position} ** TRAIL_LENGTH;
        return body;
    }

    pub fn update_trail(self: *Body) void {
        self.trail[self.trail_index] = self.position;
        self.trail_index = (self.trail_index + 1) % TRAIL_LENGTH;
    }
};

// literally every variable related to the state of the simulation
const State = struct {
    allocator: std.mem.Allocator,

    bodies: std.ArrayList(Body),
    body_count: usize,
    velocity_box_height: i32,

    focused_body_index: usize,
    focused_ui_element: enum(u32) {
        NONE = TOTAL_EDITABLE_UI,
        SIMS_PER_FRAME = 0,
        DAMPING = 1,
        RESTITUTION = 2,
        POS_X = 0x100,
        POS_Y = 0x101,
        POS_Z = 0x102,
        VEL_X = 0x200,
        VEL_Y = 0x201,
        VEL_Z = 0x202,
        MASS = 0x300,
    } = .NONE,

    simulations_per_frame: usize,
    damping: i32,
    restitution: i32,

    is_playing: bool,
    is_following: bool,
    is_text_visible: bool,
    is_controls_visible: bool,
    is_adding_body: bool,

    offset: rl.Vector3,

    controls_pos: rl.Rectangle = POSITIONS[@intFromEnum(controls_pos.VISIBLE)],

    // i hate this too but idk
    // the valueBoxFloat api needs a [:0]u8 for the string input and it pmo
    new_body: struct {
        position: rl.Vector3 = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        velocity: rl.Vector3 = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        mass: f32 = 1.0,

        pos_x_buffer: [64]u8,
        pos_y_buffer: [64]u8,
        pos_z_buffer: [64]u8,

        pos_x_str: [:0]u8 = undefined,
        pos_y_str: [:0]u8 = undefined,
        pos_z_str: [:0]u8 = undefined,

        vel_x_buffer: [64]u8,
        vel_y_buffer: [64]u8,
        vel_z_buffer: [64]u8,

        vel_x_str: [:0]u8 = undefined,
        vel_y_str: [:0]u8 = undefined,
        vel_z_str: [:0]u8 = undefined,

        mass_buffer: [64]u8,
        mass_str: [:0]u8 = undefined,

        color: rl.Color = .white,
    },

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .allocator = allocator,
            .bodies = std.ArrayList(Body).empty,
            .body_count = 0,
            .velocity_box_height = 0,
            .focused_body_index = 1,
            .simulations_per_frame = 1,
            .damping = 999,
            .restitution = 999,
            .is_playing = false,
            .is_following = false,
            .is_text_visible = true,
            .is_controls_visible = true,
            .is_adding_body = false,
            .offset = rl.Vector3{ .x = 0.0, .y = 20.0, .z = 20.0 },
            .new_body = .{
                .pos_x_buffer = .{'0'} ++ .{0} ** 63,
                .pos_y_buffer = .{'0'} ++ .{0} ** 63,
                .pos_z_buffer = .{'0'} ++ .{0} ** 63,
                .vel_x_buffer = .{'0'} ++ .{0} ** 63,
                .vel_y_buffer = .{'0'} ++ .{0} ** 63,
                .vel_z_buffer = .{'0'} ++ .{0} ** 63,
                .mass_buffer = .{'1'} ++ .{0} ** 63,
            },
        };
    }

    pub fn initialize_strings(self: *State) void {
        self.new_body.pos_x_str = self.new_body.pos_x_buffer[0..1 :0];
        self.new_body.pos_y_str = self.new_body.pos_y_buffer[0..1 :0];
        self.new_body.pos_z_str = self.new_body.pos_z_buffer[0..1 :0];

        self.new_body.vel_x_str = self.new_body.vel_x_buffer[0..1 :0];
        self.new_body.vel_y_str = self.new_body.vel_y_buffer[0..1 :0];
        self.new_body.vel_z_str = self.new_body.vel_z_buffer[0..1 :0];

        self.new_body.mass_str = self.new_body.mass_buffer[0..1 :0];
    }

    pub fn add_body(self: *State, body: Body) !void {
        try self.bodies.append(self.allocator, body);
        self.update_body_count_props();
    }

    pub fn deinit(self: *State) void {
        self.bodies.deinit(self.allocator);
    }

    pub fn update_body_count_props(self: *State) void {
        self.body_count = self.bodies.items.len;
        self.focused_body_index = self.body_count + 1;
        self.velocity_box_height = @intCast((10 * (self.body_count + 1)) + (20 * self.body_count));
    }

    pub fn toggle_is_controls_visible(self: *State) void {
        self.is_controls_visible = !self.is_controls_visible;
        self.controls_pos = POSITIONS[@intFromEnum(if (self.is_controls_visible) controls_pos.VISIBLE else controls_pos.HIDDEN)];
    }

    pub fn toggle_is_adding_body(self: *State) void {
        self.is_adding_body = !self.is_adding_body;
        self.controls_pos = POSITIONS[@intFromEnum(if (!self.is_adding_body) controls_pos.VISIBLE else controls_pos.ADDING_BODY)];
    }
};

// yoinked from some raylib example
fn hex_to_color(hex: i32) rl.Color {
    return rl.Color{
        .r = @intCast((hex >> 24) & 0xFF),
        .g = @intCast((hex >> 16) & 0xFF),
        .b = @intCast((hex >> 8) & 0xFF),
        .a = @intCast(hex & 0xFF),
    };
}

fn simulate(bodies: *std.ArrayList(Body), options: struct {
    vel_damping: i32 = 999,
    restitution_coefficient: i32 = 999,
    allow_collisions: bool = true,
}) void {
    const impulse_coefficient = 1.0 + (@as(f32, @floatFromInt(options.restitution_coefficient)) / 1000.0);
    const damping_factor = @as(f32, @floatFromInt(options.vel_damping)) / 1000.0;

    for (bodies.items, 0..) |*body, i| {
        var force = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        for (bodies.items, 0..) |*other_body, j| {
            if (i != j) {
                if (options.allow_collisions and
                    rl.checkCollisionSpheres(
                        body.position,
                        RADIUS,
                        other_body.position,
                        RADIUS,
                    ))
                {
                    const n = other_body.position.subtract(body.position).normalize();
                    const relative_velocity = other_body.velocity.subtract(body.velocity);
                    const velocity_along_normal = relative_velocity.dotProduct(n);

                    if (velocity_along_normal < 0) {
                        const impulse = (impulse_coefficient * velocity_along_normal) / (body.mass + other_body.mass);
                        body.velocity = body.velocity.add(n.scale(impulse * other_body.mass));
                        other_body.velocity = other_body.velocity.subtract(n.scale(impulse * body.mass));
                    }
                } else {
                    const direction = rl.Vector3{
                        .x = other_body.position.x - body.position.x,
                        .y = other_body.position.y - body.position.y,
                        .z = other_body.position.z - body.position.z,
                    };
                    const distance = direction.length();

                    const f = (body.mass * other_body.mass) / (distance * distance);
                    const norm_direction = direction.normalize();
                    force = force.add(norm_direction.scale(f));
                }
            }
        }
        const acceleration = force.scale(1 / body.mass);
        body.velocity = body.velocity.add(acceleration).scale(damping_factor);
        body.raw_vel = body.velocity.length();
    }

    for (bodies.items) |*body| {
        body.position = body.position.add(body.velocity);
    }
}

fn draw_grid_around(center: rl.Vector3, options: struct {
    slices: usize = 10,
    spacing: f32 = 10.0,
    color: rl.Color = .light_gray,
}) void {
    const half_size = @as(f32, @floatFromInt(options.slices)) * options.spacing / 2.0;

    for (0..options.slices + 1) |i| {
        const offset = (@as(f32, @floatFromInt(i)) * options.spacing) - half_size;

        rl.drawLine3D(
            rl.Vector3{ .x = center.x - half_size, .y = center.y, .z = center.z + offset },
            rl.Vector3{ .x = center.x + half_size, .y = center.y, .z = center.z + offset },
            options.color,
        );

        rl.drawLine3D(
            rl.Vector3{ .x = center.x + offset, .y = center.y, .z = center.z - half_size },
            rl.Vector3{ .x = center.x + offset, .y = center.y, .z = center.z + half_size },
            options.color,
        );
    }
}

fn reset(target: *std.ArrayList(Body), new: std.ArrayList(Body), allocator: std.mem.Allocator) !void {
    target.* = try new.clone(allocator);
}

pub fn main() !void {
    // === Constants ===
    const allocator = std.heap.page_allocator;

    var initial_position = try std.ArrayList(Body).initCapacity(allocator, 3);
    defer initial_position.deinit(allocator);

    // chatgpt lied to me about stable orbits existing in the 3 body problem
    // too lazy to find better ones tho so whatever
    try initial_position.append(allocator, Body.init(
        rl.Vector3{ .x = 20.0, .y = 0.0, .z = 0.0 },
        rl.Vector3{ .x = 0.0, .y = 0.0, .z = -0.17 },
        5.0,
        .red,
    ));

    try initial_position.append(allocator, Body.init(
        rl.Vector3{ .x = -10.0, .y = 0.0, .z = 17.320508 },
        rl.Vector3{ .x = 0.147198, .y = 0.0, .z = 0.084949 },
        1.0,
        .green,
    ));

    try initial_position.append(allocator, Body.init(
        rl.Vector3{ .x = -10.0, .y = 0.0, .z = -17.320508 },
        rl.Vector3{ .x = -0.147198, .y = 0.0, .z = 0.084949 },
        10.0,
        .blue,
    ));

    // === Initialization ===
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "3-body problem simulation");

    var tmp = try std.fs.cwd().createFile("style.rgsl", .{ .truncate = true });
    defer tmp.close();
    defer std.fs.cwd().deleteFile("style.rgsl") catch {};

    try tmp.writeAll(style);

    rg.loadStyle("style.rgsl");

    var camera = rl.Camera3D{
        .position = (rl.Vector3{ .x = 0.0, .y = 0.0, .z = 300.0 }),
        .target = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = rl.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    const background_color_raw = rg.getStyle(.default, .{ .default = .background_color });
    const background_color = hex_to_color(background_color_raw);

    const text_color_raw = rg.getStyle(.control11, .{ .control = .text_color_normal });
    const text_color = hex_to_color(text_color_raw);

    var state = State.init(allocator);
    state.initialize_strings();
    defer state.deinit();

    try reset(&state.bodies, initial_position, allocator);
    state.update_body_count_props();

    rl.setTargetFPS(TARGET_FPS);

    while (!rl.windowShouldClose()) {
        var update_target = if (state.is_following and state.focused_body_index < state.body_count)
            &state.offset
        else
            &camera.position;

        if (rl.isKeyDown(.w)) update_target.y += CAMERA_SPEED;
        if (rl.isKeyDown(.s)) update_target.y -= CAMERA_SPEED;
        if (rl.isKeyDown(.a)) update_target.x -= CAMERA_SPEED;
        if (rl.isKeyDown(.d)) update_target.x += CAMERA_SPEED;
        if (rl.isKeyDown(.q)) update_target.z -= CAMERA_SPEED;
        if (rl.isKeyDown(.e)) update_target.z += CAMERA_SPEED;

        if (rl.isKeyPressed(.left)) state.focused_body_index = (state.focused_body_index + state.body_count) % (state.body_count + 1);
        if (rl.isKeyPressed(.right)) state.focused_body_index = (state.focused_body_index + 1) % (state.body_count + 1);

        if (rl.isKeyPressed(.p)) state.is_playing = !state.is_playing;
        if (rl.isKeyPressed(.r)) try reset(&state.bodies, initial_position, allocator);

        if (rl.isKeyPressed(.tab)) {
            state.focused_ui_element = if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift))
                @enumFromInt(@mod(@intFromEnum(state.focused_ui_element) - 1 + TOTAL_EDITABLE_UI + 1, TOTAL_EDITABLE_UI + 1))
            else
                @enumFromInt(@mod(@intFromEnum(state.focused_ui_element) + 1, TOTAL_EDITABLE_UI + 1));
        }

        if (rl.isKeyPressed(.f)) {
            state.is_following = !state.is_following;
            if (state.is_following and state.focused_body_index < state.body_count) {
                camera.target = state.bodies.items[state.focused_body_index].position;
                camera.position = state.bodies.items[state.focused_body_index].position.add(state.offset);
            }
        }

        if (rl.isKeyPressed(.u)) state.is_text_visible = !state.is_text_visible;
        if (rl.isKeyPressed(.c)) state.toggle_is_controls_visible();

        if (state.is_playing) {
            if (state.simulations_per_frame > 0) {
                for (0..state.simulations_per_frame) |_| {
                    simulate(&state.bodies, .{
                        .vel_damping = state.damping,
                        .restitution_coefficient = state.restitution,
                    });
                }
            }
        }

        camera.target = if (state.focused_body_index < state.body_count)
            state.bodies.items[state.focused_body_index].position
        else
            rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };

        camera.position = if (state.is_following and state.focused_body_index < state.body_count)
            state.bodies.items[state.focused_body_index].position.add(state.offset)
        else
            camera.position;

        // Draw
        rl.beginDrawing();
        rl.clearBackground(background_color);
        rl.beginMode3D(camera);

        for (state.bodies.items, 0..) |*body, i| {
            body.update_trail();
            rl.drawSphere(body.position, RADIUS, body.color);

            for (0..TRAIL_LENGTH - 1) |j| {
                const index = (body.trail_index + j) % TRAIL_LENGTH;
                const next_index = (body.trail_index + j + 1) % TRAIL_LENGTH;
                rl.drawCylinderEx(
                    body.trail[index],
                    body.trail[next_index],
                    @as(f32, @floatFromInt(j + 1)) / @as(f32, @floatFromInt(TRAIL_LENGTH)),
                    @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(TRAIL_LENGTH)),
                    8,
                    rl.Color{
                        .r = body.color.r,
                        .g = body.color.g,
                        .b = body.color.b,
                        .a = @as(u8, @intFromFloat(100.0 * ((@as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(TRAIL_LENGTH)))))),
                    },
                );
            }

            if (i == state.focused_body_index) {
                rl.drawSphereWires(body.position, RADIUS * 1.2, 5, 8, text_color);
            }
        }

        draw_grid_around(camera.target, .{});

        rl.endMode3D();

        if (state.is_text_visible) {
            _ = rg.groupBox(state.controls_pos, "Controls (c)");

            if (state.is_controls_visible) {
                _ = .{ rg.spinner(
                    .{
                        .x = state.controls_pos.x + state.controls_pos.width - 110,
                        .y = state.controls_pos.y + 20,
                        .width = 100,
                        .height = 30,
                    },
                    "Sims/Frame",
                    @as(*i32, @ptrCast(&state.simulations_per_frame)),
                    1,
                    100,
                    state.focused_ui_element == .SIMS_PER_FRAME,
                ), rg.spinner(
                    .{
                        .x = state.controls_pos.x + state.controls_pos.width - 110,
                        .y = state.controls_pos.y + 60,
                        .width = 100,
                        .height = 30,
                    },
                    "Damping(/1000)",
                    &state.damping,
                    if (config.jailbreak) 0 else 900,
                    1000,
                    state.focused_ui_element == .DAMPING,
                ), rg.spinner(
                    .{
                        .x = state.controls_pos.x + state.controls_pos.width - 110,
                        .y = state.controls_pos.y + 100,
                        .width = 100,
                        .height = 30,
                    },
                    "Restitution(/1000)",
                    &state.restitution,
                    if (config.jailbreak) 0 else 900,
                    1000,
                    state.focused_ui_element == .RESTITUTION,
                ) };

                if (rg.button(
                    .{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 180,
                        .width = state.controls_pos.width - 20,
                        .height = 30,
                    },
                    "#211#Reset",
                ))
                    try reset(&state.bodies, initial_position, allocator);

                _ = rg.checkBox(
                    .{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 140,
                        .width = 30,
                        .height = 30,
                    },
                    "#131#Playing?",
                    &state.is_playing,
                );

                _ = rg.checkBox(
                    .{
                        .x = state.controls_pos.x + 120,
                        .y = state.controls_pos.y + 140,
                        .width = 30,
                        .height = 30,
                    },
                    if (state.is_following) "#113#Unfollow" else "#112#Follow",
                    &state.is_following,
                );

                if (rg.button(
                    .{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 260,
                        .width = state.controls_pos.width - 20,
                        .height = 30,
                    },
                    "#214#Add Body",
                )) state.toggle_is_adding_body();
            }

            if (state.is_adding_body) {
                _ = rg.groupBox(
                    rl.Rectangle{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 300,
                        .width = state.controls_pos.width - 20,
                        .height = 50,
                    },
                    "Position (x,y,z)",
                );

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 20,
                        .y = state.controls_pos.y + 310,
                        .width = (state.controls_pos.width - 40) / 3 - 5,
                        .height = 30,
                    },
                    "",
                    state.new_body.pos_x_str,
                    &state.new_body.position.x,
                    state.focused_ui_element == .POS_X,
                ) != 0) {
                    state.focused_ui_element = .POS_X;
                }

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 25 + (state.controls_pos.width - 40) / 3,
                        .y = state.controls_pos.y + 310,
                        .width = (state.controls_pos.width - 40) / 3 - 5,
                        .height = 30,
                    },
                    "",
                    state.new_body.pos_y_str,
                    &state.new_body.position.y,
                    state.focused_ui_element == .POS_Y,
                ) != 0) {
                    state.focused_ui_element = .POS_Y;
                }

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 30 + 2 * (state.controls_pos.width - 40) / 3,
                        .y = state.controls_pos.y + 310,
                        .width = (state.controls_pos.width - 40) / 3 - 5,
                        .height = 30,
                    },
                    "",
                    state.new_body.pos_z_str,
                    &state.new_body.position.z,
                    state.focused_ui_element == .POS_Z,
                ) != 0) {
                    state.focused_ui_element = .POS_Z;
                }

                _ = rg.groupBox(
                    rl.Rectangle{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 360,
                        .width = state.controls_pos.width - 20,
                        .height = 50,
                    },
                    "Velocity (x,y,z)",
                );

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 20,
                        .y = state.controls_pos.y + 370,
                        .width = (state.controls_pos.width - 40) / 3 - 5,
                        .height = 30,
                    },
                    "",
                    state.new_body.vel_x_str,
                    &state.new_body.velocity.x,
                    state.focused_ui_element == .VEL_X,
                ) != 0) {
                    state.focused_ui_element = .VEL_X;
                }

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 25 + (state.controls_pos.width - 40) / 3,
                        .y = state.controls_pos.y + 370,
                        .width = (state.controls_pos.width - 40) / 3 - 5,
                        .height = 30,
                    },
                    "",
                    state.new_body.vel_y_str,
                    &state.new_body.velocity.y,
                    state.focused_ui_element == .VEL_Y,
                ) != 0) {
                    state.focused_ui_element = .VEL_Y;
                }

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 30 + 2 * (state.controls_pos.width - 40) / 3,
                        .y = state.controls_pos.y + 370,
                        .width = (state.controls_pos.width - 40) / 3 - 5,
                        .height = 30,
                    },
                    "",
                    state.new_body.vel_z_str,
                    &state.new_body.velocity.z,
                    state.focused_ui_element == .VEL_Z,
                ) != 0) {
                    state.focused_ui_element = .VEL_Z;
                }

                _ = rg.colorPicker(
                    rl.Rectangle{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 420,
                        .width = (state.controls_pos.width - 20) / 2 - 25,
                        .height = 60,
                    },
                    "Color",
                    &state.new_body.color,
                );

                if (rg.valueBoxFloat(
                    .{
                        .x = state.controls_pos.x + 40 + (state.controls_pos.width - 20) / 2,
                        .y = state.controls_pos.y + 420,
                        .width = (state.controls_pos.width - 20) / 2 - 30,
                        .height = 60,
                    },
                    "Mass",
                    state.new_body.mass_str,
                    &state.new_body.mass,
                    state.focused_ui_element == .MASS,
                ) != 0) {
                    state.focused_ui_element = .MASS;
                }

                if (rg.button(
                    .{
                        .x = state.controls_pos.x + 10,
                        .y = state.controls_pos.y + 490,
                        .width = state.controls_pos.width - 20,
                        .height = 30,
                    },
                    "#8#Submit",
                )) {
                    try state.add_body(Body.init(
                        state.new_body.position,
                        state.new_body.velocity,
                        if (state.new_body.mass > 0.0) state.new_body.mass else 1.0,
                        state.new_body.color,
                    ));
                }
            }

            rl.drawText("3-Body Problem Simulation", 10, 10, 20, text_color);

            var campos_buffer: [64]u8 = undefined;
            var looking_at_buffer: [64]u8 = undefined;

            rl.drawText(
                try std.fmt.bufPrintZ(
                    &campos_buffer,
                    "Camera: {}, {}, {}",
                    if (state.is_following and state.focused_body_index < state.body_count) .{
                        state.offset.x,
                        state.offset.y,
                        state.offset.z,
                    } else .{
                        camera.position.x,
                        camera.position.y,
                        camera.position.z,
                    },
                ),
                10,
                40,
                20,
                text_color,
            );

            rl.drawText(
                try std.fmt.bufPrintZ(
                    &looking_at_buffer,
                    "Looking at: {}, {}, {}",
                    .{
                        camera.target.x,
                        camera.target.y,
                        camera.target.z,
                    },
                ),
                10,
                70,
                20,
                text_color,
            );

            rl.drawFPS(10, SCREEN_HEIGHT - 30);

            _ = rg.groupBox(
                rl.Rectangle{
                    .x = SCREEN_WIDTH - 180,
                    .y = @floatFromInt(SCREEN_HEIGHT - state.velocity_box_height - 10),
                    .width = 170,
                    .height = @floatFromInt(state.velocity_box_height),
                },
                "Velocities",
            );

            var text_left_buffer: [16]u8 = undefined;

            for (state.bodies.items, 0..) |*body, i| {
                text_left_buffer = undefined;

                _ = rg.progressBar(
                    rl.Rectangle{
                        .x = SCREEN_WIDTH - 120,
                        .y = @floatFromInt(SCREEN_HEIGHT - state.velocity_box_height + @as(i32, @intCast(i * 30))),
                        .width = 80,
                        .height = 20,
                    },
                    try std.fmt.bufPrintZ(&text_left_buffer, "Body {}", .{i + 1}),
                    ">5",
                    &body.raw_vel,
                    0.0,
                    5.0,
                );

                _ = rl.drawCircle(
                    SCREEN_WIDTH - 115 + (@as(i32, @intFromFloat((@min(body.raw_vel, 5.0) / 5.0) * 80.0))),
                    SCREEN_HEIGHT - state.velocity_box_height + 10 + @as(i32, @intCast(i * 30)),
                    5,
                    body.color,
                );
            }
        }

        rl.endDrawing();
    }

    rl.closeWindow();
}
