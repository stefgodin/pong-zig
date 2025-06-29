const std = @import("std");
const math = std.math;
const random = std.crypto.random;
const rl = @import("raylib");

const ROUND_MODE = enum {
    ROUND_START,
    ROUND_PLAY,
    ROUND_SCORE,
    ROUND_END,
};

const Settings = struct {
    win_h: i32,
    win_w: i32,
    ph: i32,
    pw: i32,
    p_speed: f32,
    border_w: i32,

    fn init() Settings {
        const s: Settings = .{
            .win_h = 100,
            .win_w = 200,
            .ph = 16,
            .pw = 4,
            .p_speed = 3, // Player height/s
            .border_w = 2,
        };
        return s;
    }
};

const Player = struct {
    rect: rl.Rectangle,
    collided: bool,
    speed: f32,
    score: i32,
};
const Ball = struct {
    rect: rl.Rectangle,
    direction: rl.Vector2,
    speed: f32,
    collided: bool,
    hidden: bool,
};
const RoundState = struct {
    t: f64,
    dt: f32,
    mode: ROUND_MODE,
    last_goal: bool, // 0 P1, 1 P2
    round_start_time: f64,
    hit_count: usize,
    p1: Player,
    p2: Player,
    ball: Ball,

    fn init(s: Settings) RoundState {
        const r: RoundState = .{
            .t = 0,
            .dt = 0,
            .mode = ROUND_MODE.ROUND_START,
            .p1 = .{
                .rect = .{
                    .x = @as(f32, @floatFromInt(s.border_w)) * 3,
                    .y = @floatFromInt(@divFloor((s.win_h - s.ph), 2)),
                    .width = @as(f32, @floatFromInt(s.pw)),
                    .height = @as(f32, @floatFromInt(s.ph)),
                },
                .collided = false,
                .speed = 3,
                .score = 0,
            },
            .p2 = .{
                .rect = .{
                    .x = @as(f32, @floatFromInt(s.win_w - (s.border_w * 3) - s.pw)),
                    .y = @floatFromInt(@divFloor((s.win_h - s.ph), 2)),
                    .width = @as(f32, @floatFromInt(s.pw)),
                    .height = @as(f32, @floatFromInt(s.ph)),
                },
                .collided = false,
                .speed = 3,
                .score = 0,
            },
            .last_goal = false,
            .round_start_time = 0,
            .hit_count = 0,
            .ball = .{
                .rect = .{
                    .x = @floatFromInt(@divFloor(s.win_w - s.pw, 2)),
                    .y = @floatFromInt(@divFloor(s.win_h - s.pw, 2)),
                    .width = @as(f32, @floatFromInt(s.pw)),
                    .height = @as(f32, @floatFromInt(s.pw)),
                },
                .direction = rl.Vector2.zero(),
                .speed = 0,
                .collided = false,
                .hidden = true,
            },
        };

        return r;
    }

    fn startNewRound(self: *RoundState, s: Settings) void {
        self.p1.rect.x = @as(f32, @floatFromInt(s.border_w)) * 3;
        self.p1.rect.y = @floatFromInt(@divFloor((s.win_h - s.ph), 2));
        self.p1.speed = 3;

        self.p2.rect.x = @as(f32, @floatFromInt(s.win_w - (s.border_w * 3) - s.pw));
        self.p2.rect.y = @floatFromInt(@divFloor((s.win_h - s.ph), 2));
        self.p2.speed = 3;

        self.last_goal = false;
        self.round_start_time = 0;
        self.hit_count = 0;

        self.ball.rect.x = @floatFromInt(@divFloor(s.win_w - s.pw, 2));
        self.ball.rect.y = @floatFromInt(@divFloor(s.win_h - s.pw, 2));
        self.ball.direction = rl.Vector2.zero();
        self.ball.speed = 0;
    }
};

const GameState = struct {
    t: f64,
    dt: f32,
    settings: Settings,
    sounds: Sounds,
    round_state: RoundState,

    fn init() !GameState {
        const settings = Settings.init();
        const gs: GameState = .{
            .t = 0,
            .dt = 0,
            .settings = settings,
            .sounds = try Sounds.init(),
            .round_state = RoundState.init(settings),
        };
        return gs;
    }
};

const Sounds = struct {
    hit: [3]rl.Sound,
    high_hit: rl.Sound,
    white: [2]rl.Sound,
    decay_white: rl.Sound,

    fn init() !Sounds {
        const hit_1 = try rl.loadSound("assets/hit_1.wav");
        const hit_2 = try rl.loadSound("assets/hit_2.wav");
        const hit_3 = try rl.loadSound("assets/hit_3.wav");
        const high_hit_1 = try rl.loadSound("assets/high_hit_1.wav");
        const white_1 = try rl.loadSound("assets/white_1.wav");
        const white_2 = try rl.loadSound("assets/white_2.wav");
        const decay_white_1 = try rl.loadSound("assets/decay_white_1.wav");
        const sounds: Sounds = .{
            .hit = .{ hit_1, hit_2, hit_3 },
            .high_hit = high_hit_1,
            .white = .{ white_1, white_2 },
            .decay_white = decay_white_1,
        };
        return sounds;
    }

    fn deinit(self: *Sounds) void {
        rl.unloadSound(self.hit[0]);
        rl.unloadSound(self.hit[1]);
        rl.unloadSound(self.hit[2]);
        rl.unloadSound(self.high_hit);
        rl.unloadSound(self.white[0]);
        rl.unloadSound(self.white[1]);
        rl.unloadSound(self.decay_white);
    }
};

pub fn main() !void {
    rl.setConfigFlags(.{ .window_undecorated = true });
    rl.initWindow(0, 0, "Pong");
    defer rl.closeWindow();
    rl.beginDrawing();
    rl.endDrawing();

    rl.setTargetFPS(60);
    const screen_rec: rl.Rectangle = .{ .height = @floatFromInt(rl.getScreenHeight()), .width = @floatFromInt(rl.getScreenWidth()), .x = 0, .y = 0 };

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    var gs = try GameState.init();

    const settings = gs.settings;

    var state = gs.round_state;
    const game_tex = try rl.loadRenderTexture(settings.win_w, settings.win_h);
    defer rl.unloadRenderTexture(game_tex);
    // Invert height to reinvert when drawing texture (weird stuff)
    const game_tex_rec: rl.Rectangle = .{ .height = @floatFromInt(-game_tex.texture.height), .width = @floatFromInt(game_tex.texture.width), .x = 0, .y = 0 };

    const min_arena_y = @as(f32, @floatFromInt(settings.border_w * 2));
    const max_arena_y = @as(f32, @floatFromInt(settings.win_h - (settings.border_w * 2)));
    const min_arena_x = @as(f32, @floatFromInt(settings.border_w * 2));
    const max_arena_x = @as(f32, @floatFromInt(settings.win_w - (settings.border_w * 2)));

    while (!rl.windowShouldClose()) {
        // Update
        gs.round_state.t = rl.getTime();
        gs.round_state.dt = rl.getFrameTime();

        if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
            rl.closeWindow();
        }

        try switch (gs.round_state.mode) {
            .ROUND_START => updateStart(&gs.round_state, &settings),
            .ROUND_PLAY => updatePlay(&gs.round_state, &settings),
            .ROUND_SCORE => updateScore(&gs.round_state, &settings),
            .ROUND_END => updateEnd(&gs.round_state, &settings),
        };

        if (rl.isKeyDown(rl.KeyboardKey.down)) {
            gs.round_state.p1.rect.y += gs.round_state.dt * gs.round_state.p1.speed * gs.round_state.p1.rect.height;
        } else if (rl.isKeyDown(rl.KeyboardKey.up)) {
            gs.round_state.p1.rect.y -= gs.round_state.dt * gs.round_state.p1.speed * gs.round_state.p1.rect.height;
        }

        gs.round_state.p1.rect.y = math.clamp(gs.round_state.p1.rect.y, min_arena_y, max_arena_y - gs.round_state.p1.rect.height);

        if (gs.round_state.p1.rect.y == min_arena_y or gs.round_state.p1.rect.y == max_arena_y) {
            if (!gs.round_state.p1.collided) {
                rl.playSound(gs.sounds.high_hit);
            }
            gs.round_state.p1.collided = true;
        } else {
            gs.round_state.p1.collided = false;
        }

        if (rl.isKeyDown(rl.KeyboardKey.s)) {
            gs.round_state.p2.rect.y += gs.round_state.dt * gs.round_state.p2.speed * gs.round_state.p2.rect.height;
        } else if (rl.isKeyDown(rl.KeyboardKey.w)) {
            gs.round_state.p2.rect.y -= gs.round_state.dt * gs.round_state.p2.speed * gs.round_state.p2.rect.height;
        }

        gs.round_state.p2.rect.y = math.clamp(gs.round_state.p2.rect.y, min_arena_y, max_arena_y - gs.round_state.p2.rect.height);

        if (gs.round_state.p2.rect.y == min_arena_y or gs.round_state.p2.rect.y == max_arena_y) {
            if (!gs.round_state.p2.collided) {
                rl.playSound(gs.sounds.high_hit);
            }
            gs.round_state.p2.collided = true;
        } else {
            gs.round_state.p2.collided = false;
        }

        if (gs.round_state.ball.hidden) {
            gs.round_state.ball.hidden = false;
            gs.round_state.ball.rect.x = (@as(f32, @floatFromInt(settings.win_w)) - gs.round_state.ball.rect.width) / 2;
            gs.round_state.ball.rect.y = (@as(f32, @floatFromInt(settings.win_h)) - gs.round_state.ball.rect.width) / 2;
            gs.round_state.round_start_time = gs.round_state.t;
        } else if (gs.round_state.ball.speed == 0 and (rl.getTime() - gs.round_state.round_start_time) >= 3.0) {
            const x: f32 = 1 - (@as(f32, @floatFromInt(random.intRangeAtMost(i32, 0, 1))) * 2);
            const y: f32 = 1 - (@as(f32, @floatFromInt(random.intRangeAtMost(i32, 0, 1))) * 2);
            gs.round_state.ball.direction = .{ .x = x, .y = y };
            gs.round_state.ball.direction = gs.round_state.ball.direction.normalize();
            gs.round_state.ball.speed = gs.round_state.ball.rect.width * 15;
        }

        const vel = gs.round_state.ball.direction.scale(gs.round_state.ball.speed);
        gs.round_state.ball.rect.x += (vel.x * gs.round_state.dt);
        gs.round_state.ball.rect.y += (vel.y * gs.round_state.dt);
        gs.round_state.ball.rect.y = math.clamp(gs.round_state.ball.rect.y, min_arena_y, max_arena_y - gs.round_state.ball.rect.height);

        // Check ball-player collision
        var p_collided = false;
        if (gs.round_state.ball.speed != 0 and gs.round_state.ball.direction.x != 0) {
            var p_rect: rl.Rectangle = undefined;

            if (gs.round_state.ball.direction.x < 0) {
                p_rect = gs.round_state.p1.rect;
            } else if (gs.round_state.ball.direction.x > 0) {
                p_rect = gs.round_state.p2.rect;
            }

            if (rl.Rectangle.checkCollision(p_rect, gs.round_state.ball.rect)) {
                p_collided = true;
                const rel_intersect = ((gs.round_state.ball.rect.y + (gs.round_state.ball.rect.height / 2)) - p_rect.y) / p_rect.height;
                var new_dir: f32 = undefined;
                if (rel_intersect < 0.1) {
                    new_dir = -0.75;
                } else if (rel_intersect < 0.3) {
                    new_dir = -0.5;
                } else if (rel_intersect < 0.7) {
                    new_dir = if (gs.round_state.ball.direction.y < 0) -0.25 else 0.25;
                } else if (rel_intersect < 0.9) {
                    new_dir = 0.5;
                } else {
                    new_dir = 0.75;
                }

                gs.round_state.ball.direction.x *= -1;
                gs.round_state.ball.direction.y = new_dir;
                gs.round_state.ball.direction = gs.round_state.ball.direction.normalize();
                gs.round_state.ball.speed *= 1.1;

                gs.round_state.p1.speed *= 1.05;
                gs.round_state.p2.speed *= 1.05;
            }
        }

        const already_collided = gs.round_state.ball.collided;
        if (p_collided) {
            gs.round_state.ball.collided = true;
            gs.round_state.hit_count += 1;
        } else if (gs.round_state.ball.rect.y == min_arena_y or gs.round_state.ball.rect.y == (max_arena_y - gs.round_state.ball.rect.height)) {
            gs.round_state.ball.collided = true;
            gs.round_state.ball.direction.y *= -1;
        } else {
            gs.round_state.ball.collided = false;
        }

        if (!already_collided and gs.round_state.ball.collided) {
            rl.setSoundPitch(gs.sounds.hit[0], 1.0 + (0.05 * @as(f32, @floatFromInt(gs.round_state.hit_count))));
            rl.playSound(gs.sounds.hit[0]);
        }

        if (gs.round_state.ball.rect.x <= min_arena_x or gs.round_state.ball.rect.x >= max_arena_x) {
            // Goal!
            if (gs.round_state.ball.rect.x <= min_arena_x) {
                gs.round_state.p2.score += 1;
            } else {
                gs.round_state.p1.score += 1;
            }

            rl.playSound(gs.sounds.decay_white);
            resetRoundState(&state, settings);
        }

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.beginTextureMode(game_tex);
        rl.clearBackground(.black);

        // Arena
        rl.drawRectangle(settings.border_w, settings.border_w, settings.win_w - (2 * settings.border_w), settings.border_w, .white);
        rl.drawRectangle(settings.border_w, settings.win_h - (2 * settings.border_w), settings.win_w - (2 * settings.border_w), settings.border_w, .white);
        var i: i32 = 0;
        const max_i = @divFloor(settings.win_h, (settings.border_w * 2)) - 2;
        while (i < max_i) {
            rl.drawRectangle(@divFloor(settings.win_w - settings.border_w, 2), @divFloor(settings.border_w, 2) + settings.border_w * 2 * (i + 1), settings.border_w, settings.border_w, .white);
            i += 1;
        }

        // P1
        rl.drawRectangleRec(gs.round_state.p1.rect, .white);
        // P2
        rl.drawRectangleRec(gs.round_state.p2.rect, .white);

        // Ball
        if (!gs.round_state.ball.hidden) {
            rl.drawRectangleRec(gs.round_state.ball.rect, .white);
        }

        rl.endTextureMode();

        rl.clearBackground(.black);
        rl.drawTexturePro(game_tex.texture, game_tex_rec, screen_rec, rl.Vector2.zero(), 0.0, .white);
    }
}

pub fn loadDefaultSettings() Settings {
    return .{
        .win_h = 100,
        .win_w = 200,
        .ph = 16,
        .pw = 4,
        .p_speed = 3, // Player height/s
        .border_w = 2,
    };
}

pub fn resetState(s: Settings) RoundState {
    return .{
        .t = 0,
        .dt = 0,
        .mode = ROUND_MODE.ROUND_START,
        .p1 = .{
            .rect = .{
                .x = @as(f32, @floatFromInt(s.border_w)) * 3,
                .y = @floatFromInt(@divFloor((s.win_h - s.ph), 2)),
                .width = @as(f32, @floatFromInt(s.pw)),
                .height = @as(f32, @floatFromInt(s.ph)),
            },
            .collided = false,
            .speed = 3,
            .score = 0,
        },
        .p2 = .{
            .rect = .{
                .x = @as(f32, @floatFromInt(s.win_w - (s.border_w * 3) - s.pw)),
                .y = @floatFromInt(@divFloor((s.win_h - s.ph), 2)),
                .width = @as(f32, @floatFromInt(s.pw)),
                .height = @as(f32, @floatFromInt(s.ph)),
            },
            .collided = false,
            .speed = 3,
            .score = 0,
        },
        .last_goal = false,
        .round_start_time = 0,
        .hit_count = 0,
        .ball = .{
            .rect = .{
                .x = @floatFromInt(@divFloor(s.win_w - s.pw, 2)),
                .y = @floatFromInt(@divFloor(s.win_h - s.pw, 2)),
                .width = @as(f32, @floatFromInt(s.pw)),
                .height = @as(f32, @floatFromInt(s.pw)),
            },
            .direction = rl.Vector2.zero(),
            .speed = 0,
            .collided = false,
            .hidden = true,
        },
    };
}

pub fn resetRoundState(state: *RoundState, s: Settings) void {
    state.p1.rect.x = @as(f32, @floatFromInt(s.border_w)) * 3;
    state.p1.rect.y = @floatFromInt(@divFloor((s.win_h - s.ph), 2));
    state.p1.speed = 3;

    state.p2.rect.x = @as(f32, @floatFromInt(s.win_w - (s.border_w * 3) - s.pw));
    state.p2.rect.y = @floatFromInt(@divFloor((s.win_h - s.ph), 2));
    state.p2.speed = 3;

    state.last_goal = false;
    state.round_start_time = 0;
    state.hit_count = 0;

    state.ball.rect.x = @floatFromInt(@divFloor(s.win_w - s.pw, 2));
    state.ball.rect.y = @floatFromInt(@divFloor(s.win_h - s.pw, 2));
    state.ball.direction = rl.Vector2.zero();
    state.ball.speed = 0;
}

pub fn updateStart(state: *RoundState, settings: *const Settings) !void {
    _ = state.dt + settings.p_speed;
}
pub fn renderStart() !void {}

pub fn updatePlay(state: *RoundState, settings: *const Settings) !void {
    _ = state.dt + settings.p_speed;
}
pub fn renderPlay() !void {}

pub fn updateScore(state: *RoundState, settings: *const Settings) !void {
    _ = state.dt + settings.p_speed;
}
pub fn renderScore() !void {}

pub fn updateEnd(state: *RoundState, settings: *const Settings) !void {
    _ = state.dt + settings.p_speed;
}
pub fn renderEnd() !void {}
