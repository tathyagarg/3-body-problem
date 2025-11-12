const std = @import("std");
const rl = @import("raylib");

const BASE_SCALE = 1.0;
const BODY_COUNT = 3;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;

const TARGET_FPS = 60;
const GRAVITATIONAL_CONSTANT = 1.0;
const SIMULATIONS_PER_FRAME = 1;

const CAMERA_SPEED = 3;

const Body = struct {
    aPosition: rl.Vector3,
    aVelocity: rl.Vector3,
    mass: f32,

    color: rl.Color = .blue,

    pub fn init(position: rl.Vector3, velocity: rl.Vector3, mass: f32, color: rl.Color, options: struct { scale: f32 = BASE_SCALE }) Body {
        return Body{
            .aPosition = position.scale(options.scale),
            .aVelocity = velocity.scale(options.scale),
            .mass = mass * options.scale,
            .color = color,
        };
    }
};

fn simulate(bodies: *[BODY_COUNT]Body) void {
    for (bodies, 0..) |*body, i| {
        var force = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        for (bodies, 0..) |other_body, j| {
            if (i != j) {
                const direction = rl.Vector3{
                    .x = other_body.aPosition.x - body.aPosition.x,
                    .y = other_body.aPosition.y - body.aPosition.y,
                    .z = other_body.aPosition.z - body.aPosition.z,
                };
                const distance = direction.length();
                if (distance < 0.1) continue;

                const f = GRAVITATIONAL_CONSTANT * (body.mass * other_body.mass) / (distance * distance);
                const norm_direction = direction.normalize();
                force = force.add(norm_direction.scale(f));
            }
        }
        const acceleration = force.scale(1 / body.mass);
        // std.debug.print("Body {} Acceleration: ({}, {}, {})\n", .{ i, acceleration.x, acceleration.y, acceleration.z });
        body.aVelocity = body.aVelocity.add(acceleration);
    }

    for (bodies) |*body| {
        body.aPosition = body.aPosition.add(body.aVelocity);
    }
}

fn draw_grid_around(center: rl.Vector3, options: struct {
    slices: usize = 10,
    spacing: f32 = 10.0 * BASE_SCALE,
}) void {
    const half_size = @as(f32, @floatFromInt(options.slices)) * options.spacing / 2.0;

    for (0..options.slices + 1) |i| {
        const offset = (@as(f32, @floatFromInt(i)) * options.spacing) - half_size;

        rl.drawLine3D(
            rl.Vector3{ .x = center.x - half_size, .y = center.y, .z = center.z + offset },
            rl.Vector3{ .x = center.x + half_size, .y = center.y, .z = center.z + offset },
            .light_gray,
        );

        rl.drawLine3D(
            rl.Vector3{ .x = center.x + offset, .y = center.y, .z = center.z - half_size },
            rl.Vector3{ .x = center.x + offset, .y = center.y, .z = center.z + half_size },
            .light_gray,
        );
    }
}

pub fn main() !void {
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "3-body problem simulation");

    var camera = rl.Camera3D{
        .position = (rl.Vector3{ .x = 0.0, .y = 0.0, .z = 30.0 }).scale(BASE_SCALE),
        .target = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .up = rl.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 45.0,
        .projection = .perspective,
    };

    var bodies = [BODY_COUNT]Body{
        // 3 body system
        Body.init(
            rl.Vector3{ .x = -15.0, .y = 0.0, .z = -15.0 },
            rl.Vector3{ .x = 0.0, .y = -1.0, .z = 0.0 },
            1.0,
            .red,
            .{},
        ),
        Body.init(
            rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 },
            rl.Vector3{ .x = 0.0, .y = -0.0, .z = 0.0 },
            20.0,
            .green,
            .{},
        ),
        Body.init(
            rl.Vector3{ .x = 15.0, .y = 0.0, .z = 15.0 },
            rl.Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 },
            1.0,
            .blue,
            .{},
        ),
    };

    rl.setTargetFPS(TARGET_FPS);

    var focused_body_index: usize = 3;

    while (!rl.windowShouldClose()) {
        if (rl.isKeyDown(.w)) camera.position.y += CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.s)) camera.position.y -= CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.a)) camera.position.x -= CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.d)) camera.position.x += CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.q)) camera.position.z -= CAMERA_SPEED * BASE_SCALE;
        if (rl.isKeyDown(.e)) camera.position.z += CAMERA_SPEED * BASE_SCALE;

        if (rl.isKeyPressed(.one)) focused_body_index = 0;
        if (rl.isKeyPressed(.two)) focused_body_index = 1;
        if (rl.isKeyPressed(.three)) focused_body_index = 2;
        if (rl.isKeyPressed(.left)) focused_body_index = (focused_body_index + BODY_COUNT - 1) % BODY_COUNT;
        if (rl.isKeyPressed(.right)) focused_body_index = (focused_body_index + 1) % BODY_COUNT;

        if (SIMULATIONS_PER_FRAME > 0) {
            for (0..SIMULATIONS_PER_FRAME) |_| {
                simulate(&bodies);
            }
        }

        if (focused_body_index < BODY_COUNT)
            camera.target = bodies[focused_body_index].aPosition;

        // Draw
        rl.beginDrawing();
        rl.clearBackground(.white);
        rl.beginMode3D(camera);

        for (bodies) |body| {
            rl.drawSphere(body.aPosition, 2.5, body.color);
        }

        draw_grid_around(camera.target, .{});

        rl.endMode3D();
        rl.drawText("3-Body Problem Simulation", 10, 10, 20, .dark_gray);

        var buffer: [64]u8 = undefined;

        rl.drawText(
            try std.fmt.bufPrintZ(
                &buffer,
                "{}, {}, {}",
                .{
                    camera.position.x / BASE_SCALE,
                    camera.position.y / BASE_SCALE,
                    camera.position.z / BASE_SCALE,
                },
            ),
            10,
            40,
            20,
            .dark_gray,
        );

        rl.endDrawing();
    }

    rl.closeWindow();
}
