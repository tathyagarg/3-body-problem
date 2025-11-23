const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const config = @import("config");

const style = @embedFile("style");

const RADIUS = 2.5;

const SCREEN_WIDTH: i32 = config.screen_width;
const SCREEN_HEIGHT: i32 = config.screen_height;

const TARGET_FPS = 60;

const CAMERA_SPEED = 3;
const TRAIL_LENGTH = 100;
const TOTAL_EDITABLE_UI = 3;

const COLOUMB_CONSTANT = -5;

// i hate that this is hardcoded but im not about to write a dynamic ui system rn
const POSITIONS: [3]rl.Rectangle = .{
    .{ .x = SCREEN_WIDTH - 240, .y = 10, .width = 230, .height = 290 }, // VISIBLE
    .{ .x = SCREEN_WIDTH - 240, .y = 10, .width = 230, .height = 10 }, // HIDDEN
    .{ .x = SCREEN_WIDTH - 240, .y = 10, .width = 230, .height = 560 }, // ADDING_BODY
};

const ControlsPos = enum(usize) {
    VISIBLE,
    HIDDEN,
    ADDING_BODY,
};

const Body = struct {
    position: rl.Vector3,
    velocity: rl.Vector3,

    mass: f32,
    charge: f32 = 0.0,

    color: rl.Color = .blue,

    // used for velocity bar display
    raw_vel: f32 = 0.0,

    trail: [TRAIL_LENGTH]rl.Vector3 = undefined,
    trail_index: usize = 0,

    pub fn init(position: rl.Vector3, velocity: rl.Vector3, mass: f32, color: rl.Color, charge: f32) Body {
        var body = Body{
            .position = position,
            .velocity = velocity,
            .mass = mass,
            .color = color,
            .charge = charge,
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

const EditingBody = struct {
    position: rl.Vector3 = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    velocity: rl.Vector3 = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    mass: f32 = 1.0,
    charge: f32 = 0.0,

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

    charge_buffer: [64]u8,
    charge_str: [:0]u8 = undefined,

    color: rl.Color = .white,

    pub fn default() EditingBody {
        return EditingBody{
            .pos_x_buffer = .{'0'} ++ .{0} ** 63,
            .pos_y_buffer = .{'0'} ++ .{0} ** 63,
            .pos_z_buffer = .{'0'} ++ .{0} ** 63,
            .vel_x_buffer = .{'0'} ++ .{0} ** 63,
            .vel_y_buffer = .{'0'} ++ .{0} ** 63,
            .vel_z_buffer = .{'0'} ++ .{0} ** 63,
            .mass_buffer = .{'1'} ++ .{0} ** 63,
            .charge_buffer = .{'0'} ++ .{0} ** 63,
        };
    }

    pub fn initialize_strings(self: *EditingBody) void {
        self.pos_x_str = self.pos_x_buffer[0..1 :0];
        self.pos_y_str = self.pos_y_buffer[0..1 :0];
        self.pos_z_str = self.pos_z_buffer[0..1 :0];

        self.vel_x_str = self.vel_x_buffer[0..1 :0];
        self.vel_y_str = self.vel_y_buffer[0..1 :0];
        self.vel_z_str = self.vel_z_buffer[0..1 :0];

        self.mass_str = self.mass_buffer[0..1 :0];
        self.charge_str = self.charge_buffer[0..1 :0];
    }
};

const UISizing = struct {
    base_x_offset: f32, // state.controls_pos.x + 10;
    base_x_offset_spinner: f32, // = state.controls_pos.x + 120;

    base_y_offset: f32, // = state.controls_pos.y + 10;

    base_height: f32, // = 30.0;

    base_width: f32, // = 100.0;
    base_width_full: f32, // = state.controls_pos.width - 20;

    padding: f32, // = 10.0;

    position_y_offset: f32, // get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 7);
    velocity_y_offset: f32, // get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 8) + (2 * state.ui.padding);

    third_width: f32,
    half_width: f32,

    font_size: i32,
};

// literally every variable related to the state of the simulation
const State = struct {
    allocator: std.mem.Allocator,

    bodies: std.ArrayList(Body) = std.ArrayList(Body).empty,
    body_count: usize = 0,
    velocity_box_height: i32 = 0,

    focused_body_index: usize = 0,
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
        CHARGE = 0x301,
    } = .NONE,

    simulations_per_frame: usize = 1,
    damping: i32 = 1000,
    restitution: i32 = 1000,

    is_playing: bool = false,
    is_following: bool = false,
    is_text_visible: bool = true,
    is_collisions_allowed: bool = true,

    offset: rl.Vector3 = rl.Vector3{ .x = 0.0, .y = 20.0, .z = 20.0 },

    raw_controls_pos: ControlsPos = .VISIBLE,
    controls_pos: rl.Rectangle = POSITIONS[@intFromEnum(ControlsPos.VISIBLE)],

    // i hate this too but idk
    // the valueBoxFloat api needs a [:0]u8 for the string input and it pmo
    new_body: EditingBody = EditingBody.default(),
    initial_position: ?std.ArrayList(Body) = null,

    colors: struct {
        text_color: rl.Color = .white,
        background_color: rl.Color = .black,
    } = .{},

    camera: *rl.Camera3D = undefined,
    ui: UISizing,

    pub fn init(allocator: std.mem.Allocator, options: struct {
        initial_position: std.ArrayList(Body),
        colors: struct {
            text_color: rl.Color,
            background_color: rl.Color,
        },
        camera: *rl.Camera3D,
        ui_sizing: ?UISizing,
    }) State {
        return State{
            .allocator = allocator,
            .initial_position = options.initial_position,
            .colors = .{
                .text_color = options.colors.text_color,
                .background_color = options.colors.background_color,
            },
            .camera = options.camera,
            .ui = if (options.ui_sizing) |ui_| ui_ else UISizing{
                .base_x_offset = @as(f32, @floatFromInt(SCREEN_WIDTH)) - 240.0 + 10.0,
                .base_x_offset_spinner = @as(f32, @floatFromInt(SCREEN_WIDTH)) - 240.0 + 120.0,
                .base_y_offset = 10.0,
                .base_height = 30.0,
                .base_width = 100.0,
                .base_width_full = 230.0 - 20.0,
                .padding = 10.0,
                .position_y_offset = get_ui_y_offset(10.0, 30.0, 10.0, 7),
                .velocity_y_offset = get_ui_y_offset(10.0, 30.0, 10.0, 8) + (2 * 10.0),
                .third_width = (230.0 - 20.0 - (2.0 * 10.0)) / 3.0 - (10.0 / 2.0),
                .half_width = (230.0 - 20.0) / 2.0,
                .font_size = 20,
            },
        };
    }

    pub fn update_ui_sizing(self: *State) void {
        self.ui.base_x_offset = self.controls_pos.x + 10;
        self.ui.base_x_offset_spinner = self.controls_pos.x + 120;
        self.ui.base_y_offset = self.controls_pos.y + 10;
        self.ui.base_width_full = self.controls_pos.width - 20;

        self.ui.position_y_offset = get_ui_y_offset(
            self.ui.base_y_offset,
            self.ui.base_height,
            self.ui.padding,
            7,
        );

        self.ui.velocity_y_offset = get_ui_y_offset(
            self.ui.base_y_offset,
            self.ui.base_height,
            self.ui.padding,
            8,
        ) + (2 * self.ui.padding);

        self.ui.third_width =
            (self.ui.base_width_full - (2 * self.ui.padding)) / 3 - (self.ui.padding / 2);

        self.ui.half_width = self.ui.base_width_full / 2;
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
        self.focused_body_index = self.body_count;
        self.velocity_box_height = @intCast((10 * (self.body_count + 1)) + (20 * self.body_count));
    }

    pub fn toggle_is_controls_visible(self: *State) void {
        self.raw_controls_pos = if (self.raw_controls_pos == .HIDDEN) .VISIBLE else .HIDDEN;
        self.controls_pos = POSITIONS[@intFromEnum(self.raw_controls_pos)];
        self.update_ui_sizing();
    }

    pub fn toggle_is_adding_body(self: *State) !void {
        self.raw_controls_pos = if (self.raw_controls_pos != .ADDING_BODY) .ADDING_BODY else .VISIBLE;
        self.controls_pos = POSITIONS[@intFromEnum(self.raw_controls_pos)];
        self.update_ui_sizing();

        try self.update_buffer_contents();
    }

    pub fn update_buffer_contents(self: *State) !void {
        if (self.focused_body_index != self.body_count) {
            const body = self.bodies.items[self.focused_body_index];
            self.new_body.position = body.position;
            self.new_body.velocity = body.velocity;
            self.new_body.mass = body.mass;
            self.new_body.color = body.color;
            self.new_body.charge = body.charge;

            _ = try std.fmt.bufPrintZ(&self.new_body.pos_x_buffer, "{}", .{body.position.x});
            _ = try std.fmt.bufPrintZ(&self.new_body.pos_y_buffer, "{}", .{body.position.y});
            _ = try std.fmt.bufPrintZ(&self.new_body.pos_z_buffer, "{}", .{body.position.z});

            _ = try std.fmt.bufPrintZ(&self.new_body.vel_x_buffer, "{}", .{body.velocity.x});
            _ = try std.fmt.bufPrintZ(&self.new_body.vel_y_buffer, "{}", .{body.velocity.y});
            _ = try std.fmt.bufPrintZ(&self.new_body.vel_z_buffer, "{}", .{body.velocity.z});

            _ = try std.fmt.bufPrintZ(&self.new_body.mass_buffer, "{}", .{body.mass});
            _ = try std.fmt.bufPrintZ(&self.new_body.charge_buffer, "{}", .{body.charge});
        } else {
            self.new_body = EditingBody.default();
            self.new_body.initialize_strings();
        }
    }

    pub fn reset(self: *State, new: ?std.ArrayList(Body)) !void {
        self.bodies = if (new) |new_| try new_.clone(self.allocator) else if (self.initial_position) |initial| try initial.clone(self.allocator) else std.ArrayList(Body).empty;
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
        var force = rl.Vector3.zero();
        for (bodies.items, 0..) |*other_body, j| {
            if (i != j) {
                if (options.allow_collisions and
                    rl.checkCollisionSpheres(body.position, RADIUS, other_body.position, RADIUS))
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
                    const direction = other_body.position.subtract(body.position);
                    const distance = direction.length();

                    // Gravitational Force
                    const f = (body.mass * other_body.mass) / (distance * distance);
                    const norm_direction = direction.normalize();
                    force = force.add(norm_direction.scale(f));

                    // Electrostatic Force
                    const inverse_distance = 1.0 / distance;
                    const charge_direction = direction.normalize();

                    const charge_product = body.charge * other_body.charge;
                    const electrostatic_force_magnitude = COLOUMB_CONSTANT * charge_product * inverse_distance * inverse_distance;

                    const electrostatic_force = charge_direction.scale(electrostatic_force_magnitude / body.mass);
                    force = force.add(electrostatic_force);
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

fn get_ui_y_offset(base_y_offset: f32, base_height: f32, padding: f32, n: usize) f32 {
    return base_y_offset + (padding + base_height) * @as(f32, @floatFromInt(n));
}

fn draw_ui(state: *State) !void {
    if (state.is_text_visible) {
        _ = rg.groupBox(state.controls_pos, "Controls (c)");

        if (state.raw_controls_pos == .VISIBLE or state.raw_controls_pos == .ADDING_BODY) {
            _ = .{ rg.spinner(
                .{
                    .x = state.ui.base_x_offset_spinner,
                    .y = state.ui.base_y_offset,
                    .width = state.ui.base_width,
                    .height = state.ui.base_height,
                },
                "Sims/Frame",
                @as(*i32, @ptrCast(&state.simulations_per_frame)),
                1,
                if (config.jailbreak) 1000 else 100,
                state.focused_ui_element == .SIMS_PER_FRAME,
            ), rg.spinner(
                .{
                    .x = state.ui.base_x_offset_spinner,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 1),
                    .width = state.ui.base_width,
                    .height = state.ui.base_height,
                },
                "Damping(/1000)",
                &state.damping,
                if (config.jailbreak) 0 else 900,
                1000,
                state.focused_ui_element == .DAMPING,
            ), rg.spinner(
                .{
                    .x = state.ui.base_x_offset_spinner,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 2),
                    .width = state.ui.base_width,
                    .height = state.ui.base_height,
                },
                "Restitution(/1000)",
                &state.restitution,
                if (config.jailbreak) 0 else 900,
                1000,
                state.focused_ui_element == .RESTITUTION,
            ) };

            _ = rg.checkBox(
                .{
                    .x = state.ui.base_x_offset,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 3),
                    .width = state.ui.base_height, // ts looks like a typo but i need the box to be one square
                    .height = state.ui.base_height,
                },
                "#131#Playing?",
                &state.is_playing,
            );

            _ = rg.checkBox(
                .{
                    // 110 is the perfect offset so that its away from the playing checkbox but idk how to make it a const with a reasonable name
                    .x = state.ui.base_x_offset + 110,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 3),
                    .width = state.ui.base_height,
                    .height = state.ui.base_height,
                },
                if (state.is_following) "#113#Unfollow" else "#112#Follow",
                &state.is_following,
            );

            _ = rg.checkBox(
                .{
                    .x = state.ui.base_x_offset,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 4),
                    .width = state.ui.base_height,
                    .height = state.ui.base_height,
                },
                "#155#Collisions",
                &state.is_collisions_allowed,
            );

            if (rg.button(
                .{
                    .x = state.ui.base_x_offset,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 5),
                    .width = state.ui.base_width_full,
                    .height = state.ui.base_height,
                },
                "#211#Reset",
            ))
                try state.reset(null);

            if (rg.button(
                .{
                    .x = state.ui.base_x_offset,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 6),
                    .width = state.ui.base_width_full,
                    .height = state.ui.base_height,
                },
                if (state.focused_body_index == state.body_count) "#214#Add Body" else "#22#Edit Body",
            )) try state.toggle_is_adding_body();
        }

        if (state.raw_controls_pos == .ADDING_BODY) {
            _ = rg.groupBox(
                rl.Rectangle{
                    .x = state.ui.base_x_offset,
                    .y = state.ui.position_y_offset,
                    .width = state.ui.base_width_full,
                    .height = state.ui.base_height + (2 * state.ui.padding),
                },
                "Position (x,y,z)",
            );

            if (rg.valueBoxFloat(
                .{
                    .x = state.ui.base_x_offset + state.ui.padding,
                    .y = get_ui_y_offset(
                        state.ui.position_y_offset + state.ui.padding,
                        state.ui.base_height,
                        state.ui.padding,
                        0,
                    ),
                    .width = state.ui.third_width,
                    .height = state.ui.base_height,
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
                    .x = state.ui.base_x_offset + state.ui.third_width + (2 * state.ui.padding),
                    .y = get_ui_y_offset(
                        state.ui.position_y_offset + state.ui.padding,
                        state.ui.base_height,
                        state.ui.padding,
                        0,
                    ),
                    .width = state.ui.third_width,
                    .height = state.ui.base_height,
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
                    .x = state.ui.base_x_offset + (2 * state.ui.third_width) + (3 * state.ui.padding),
                    .y = get_ui_y_offset(
                        state.ui.position_y_offset + state.ui.padding,
                        state.ui.base_height,
                        state.ui.padding,
                        0,
                    ),
                    .width = state.ui.third_width,
                    .height = state.ui.base_height,
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
                    .x = state.ui.base_x_offset,
                    .y = state.ui.velocity_y_offset,
                    .width = state.ui.base_width_full,
                    .height = state.ui.base_height + (2 * state.ui.padding),
                },
                "Velocity (x,y,z)",
            );

            if (rg.valueBoxFloat(
                .{
                    .x = state.ui.base_x_offset + state.ui.padding,
                    .y = state.ui.velocity_y_offset + state.ui.padding,
                    .width = state.ui.third_width,
                    .height = state.ui.base_height,
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
                    .x = state.ui.base_x_offset + state.ui.third_width + (2 * state.ui.padding),
                    .y = state.ui.velocity_y_offset + state.ui.padding,
                    .width = state.ui.third_width,
                    .height = state.ui.base_height,
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
                    .x = state.ui.base_x_offset + (2 * state.ui.third_width) + (3 * state.ui.padding),
                    .y = state.ui.velocity_y_offset + state.ui.padding,
                    .width = state.ui.third_width,
                    .height = state.ui.base_height,
                },
                "",
                state.new_body.vel_z_str,
                &state.new_body.velocity.z,
                state.focused_ui_element == .VEL_Z,
            ) != 0) {
                state.focused_ui_element = .VEL_Z;
            }

            if (rg.valueBoxFloat(
                .{
                    .x = state.ui.base_x_offset + 30,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 9) + (4 * state.ui.padding),
                    .width = state.ui.half_width - 30 - state.ui.padding,
                    .height = state.ui.base_height,
                },
                "Mass",
                state.new_body.mass_str,
                &state.new_body.mass,
                state.focused_ui_element == .MASS,
            ) != 0) {
                state.focused_ui_element = .MASS;
            }

            if (rg.valueBoxFloat(
                .{
                    .x = state.ui.base_x_offset + state.ui.half_width + state.ui.padding + 30,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 9) + (4 * state.ui.padding),
                    .width = state.ui.half_width - 30 - state.ui.padding,
                    .height = state.ui.base_height,
                },
                "Charge",
                state.new_body.charge_str,
                &state.new_body.charge,
                state.focused_ui_element == .CHARGE,
            ) != 0) {
                state.focused_ui_element = .CHARGE;
            }

            _ = rg.colorPicker(
                rl.Rectangle{
                    .x = state.ui.base_x_offset,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 10) + (4 * state.ui.padding),
                    .width = state.ui.base_width_full - 25,
                    .height = 2 * state.ui.base_height,
                },
                "Color",
                &state.new_body.color,
            );

            if (rg.button(
                .{
                    .x = state.ui.base_x_offset,
                    .y = get_ui_y_offset(state.ui.base_y_offset, state.ui.base_height, state.ui.padding, 12) + (3 * state.ui.padding),
                    .width = state.ui.base_width_full,
                    .height = state.ui.base_height,
                },
                "#8#Submit",
            )) {
                if (state.focused_body_index == state.body_count) {
                    try state.add_body(Body.init(
                        state.new_body.position,
                        state.new_body.velocity,
                        if (state.new_body.mass > 0.0) state.new_body.mass else 1.0,
                        state.new_body.color,
                        state.new_body.charge,
                    ));
                } else {
                    state.bodies.items[state.focused_body_index] = Body.init(
                        state.new_body.position,
                        state.new_body.velocity,
                        if (state.new_body.mass > 0.0) state.new_body.mass else 1.0,
                        state.new_body.color,
                        state.new_body.charge,
                    );
                }
            }
        }

        rl.drawText(
            "3-Body Problem Simulation",
            @intFromFloat(state.ui.padding),
            @intFromFloat(state.ui.padding),
            state.ui.font_size,
            state.colors.text_color,
        );

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
                    state.camera.position.x,
                    state.camera.position.y,
                    state.camera.position.z,
                },
            ),
            @intFromFloat(state.ui.padding),
            @intFromFloat(get_ui_y_offset(
                state.ui.padding,
                @floatFromInt(state.ui.font_size),
                state.ui.padding,
                1,
            )),
            state.ui.font_size,
            state.colors.text_color,
        );

        rl.drawText(
            try std.fmt.bufPrintZ(
                &looking_at_buffer,
                "Looking at: {}, {}, {}",
                .{
                    state.camera.target.x,
                    state.camera.target.y,
                    state.camera.target.z,
                },
            ),
            @intFromFloat(state.ui.padding),
            @intFromFloat(get_ui_y_offset(
                state.ui.padding,
                @floatFromInt(state.ui.font_size),
                state.ui.padding,
                2,
            )),
            state.ui.font_size,
            state.colors.text_color,
        );

        rl.drawFPS(@intFromFloat(state.ui.padding), SCREEN_HEIGHT - 30);

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
}

pub fn main() !void {
    // === Constants ===
    const allocator = std.heap.page_allocator;

    var initial_position = try std.ArrayList(Body).initCapacity(allocator, 3);
    defer initial_position.deinit(allocator);

    // chatgpt lied to me about stable orbits existing in the 3 body problem
    // too lazy to find better ones tho so whatever
    try initial_position.append(allocator, Body.init(
        rl.Vector3{ .x = 10.0, .y = 0.0, .z = 0.0 },
        rl.Vector3{ .x = 0.0, .y = 0.0, .z = -0.0 },
        1.0,
        .red,
        1.0,
    ));

    try initial_position.append(allocator, Body.init(
        rl.Vector3{ .x = -10.0, .y = 0.0, .z = 0.0 },
        // fall towards red
        // rl.Vector3{ .x = 0.147198, .y = 0.0, .z = -0.084949 },
        rl.Vector3{ .x = 0.0, .y = 0.0, .z = -0.0 },
        1.0,
        .green,
        -1.0,
    ));

    try initial_position.append(allocator, Body.init(
        rl.Vector3{ .x = -10.0, .y = 0.0, .z = -17.320508 },
        rl.Vector3{ .x = -0.147198, .y = 0.0, .z = 0.084949 },
        2.5,
        .blue,
        0.0,
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

    var state = State.init(allocator, .{
        .initial_position = initial_position,
        .colors = .{
            .text_color = text_color,
            .background_color = background_color,
        },
        .camera = &camera,
        .ui_sizing = null,
    });
    state.update_ui_sizing();
    state.new_body.initialize_strings();
    defer state.deinit();

    try state.reset(null);
    state.update_body_count_props();

    rl.setTargetFPS(TARGET_FPS);

    while (!rl.windowShouldClose()) {
        var update_target = if (state.is_following and state.focused_body_index != state.body_count)
            &state.offset
        else
            &camera.position;

        if (rl.isKeyDown(.w)) update_target.y += CAMERA_SPEED;
        if (rl.isKeyDown(.s)) update_target.y -= CAMERA_SPEED;
        if (rl.isKeyDown(.a)) update_target.x -= CAMERA_SPEED;
        if (rl.isKeyDown(.d)) update_target.x += CAMERA_SPEED;
        if (rl.isKeyDown(.q)) update_target.z -= CAMERA_SPEED;
        if (rl.isKeyDown(.e)) update_target.z += CAMERA_SPEED;

        if (rl.isKeyPressed(.left)) {
            state.focused_body_index = (state.focused_body_index + state.body_count) % (state.body_count + 1);
            try state.update_buffer_contents();
        }
        if (rl.isKeyPressed(.right)) {
            state.focused_body_index = (state.focused_body_index + 1) % (state.body_count + 1);
            try state.update_buffer_contents();
        }

        if (rl.isKeyPressed(.p) or rl.isKeyPressed(.space)) state.is_playing = !state.is_playing;
        if (rl.isKeyPressed(.r)) try state.reset(null);

        if (rl.isKeyPressed(.tab)) {
            state.focused_ui_element = if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift))
                @enumFromInt(@mod(@intFromEnum(state.focused_ui_element) + TOTAL_EDITABLE_UI, TOTAL_EDITABLE_UI + 1))
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
                        .allow_collisions = state.is_collisions_allowed,
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

        rl.drawRectangle(
            @intFromFloat(state.controls_pos.x),
            @intFromFloat(state.controls_pos.y),
            @intFromFloat(state.controls_pos.width),
            @intFromFloat(state.controls_pos.height),
            rl.Color{
                .r = state.colors.background_color.r -| 10,
                .g = state.colors.background_color.g -| 10,
                .b = state.colors.background_color.b -| 10,
                .a = 200,
            },
        );
        try draw_ui(&state);

        rl.endDrawing();
    }

    rl.closeWindow();
}
