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
    p_base_speed: f32,
    border_w: i32,

    fn init() Settings {
        const s: Settings = .{
            .win_h = 100,
            .win_w = 200,
            .ph = 16,
            .pw = 4,
            .p_base_speed = 3, // Player height/s
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
    last_mode: ROUND_MODE,
    mode: ROUND_MODE,
    mode_change_t: f64,
    hit_count: usize,
    p1: Player,
    p2: Player,
    ball: Ball,

    fn init(s: Settings) RoundState {
        const r: RoundState = .{
            .last_mode = .ROUND_END,
            .mode = .ROUND_START,
            .p1 = .{
                .rect = .{
                    .x = @as(f32, @floatFromInt(s.border_w)) * 3,
                    .y = 0,
                    .width = @as(f32, @floatFromInt(s.pw)),
                    .height = @as(f32, @floatFromInt(s.ph)),
                },
                .collided = false,
                .speed = s.p_base_speed,
                .score = 0,
            },
            .p2 = .{
                .rect = .{
                    .x = @as(f32, @floatFromInt(s.win_w - (s.border_w * 3) - s.pw)),
                    .y = 0,
                    .width = @as(f32, @floatFromInt(s.pw)),
                    .height = @as(f32, @floatFromInt(s.ph)),
                },
                .collided = false,
                .speed = s.p_base_speed,
                .score = 0,
            },
            .mode_change_t = 0,
            .hit_count = 0,
            .ball = .{
                .rect = .{
                    .x = 0,
                    .y = 0,
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
};

const GAME_MODE = enum {
    MAIN_MENU,
    PAUSE_MENU,
    PLAY,
};
const GameState = struct {
    t: f64,
    dt: f32,
    mode: GAME_MODE,
    settings: Settings,
    sounds: Sounds,
    round_state: RoundState,
    arena_rect: rl.Rectangle,
    screen_rect: rl.Rectangle,

    fn init() !GameState {
        const settings = Settings.init();
        const gs: GameState = .{
            .t = 0,
            .dt = 0,
            .mode = .MAIN_MENU,
            .settings = settings,
            .sounds = try Sounds.init(),
            .round_state = RoundState.init(settings),
            .arena_rect = .{
                .x = @as(f32, @floatFromInt(settings.border_w * 2)),
                .y = @as(f32, @floatFromInt(settings.border_w * 2)),
                .width = @as(f32, @floatFromInt(settings.win_w - (settings.border_w * 4))),
                .height = @as(f32, @floatFromInt(settings.win_h - (settings.border_w * 4))),
            },
            .screen_rect = .{
                .x = 0,
                .y = 0,
                .height = @floatFromInt(rl.getScreenHeight()),
                .width = @floatFromInt(rl.getScreenWidth()),
            },
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

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    var gs = try GameState.init();

    const settings = gs.settings;

    const game_tex = try rl.loadRenderTexture(settings.win_w, settings.win_h);
    defer rl.unloadRenderTexture(game_tex);
    // Invert height to reinvert when drawing texture (weird stuff)
    const game_tex_rec: rl.Rectangle = .{ .height = @floatFromInt(-game_tex.texture.height), .width = @floatFromInt(game_tex.texture.width), .x = 0, .y = 0 };

    while (!rl.windowShouldClose()) {
        // Update
        gs.t = rl.getTime();
        gs.dt = rl.getFrameTime();

        if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
            rl.closeWindow();
        }

        try switch (gs.mode) {
            .MAIN_MENU => updateMainMenu(&gs),
            .PAUSE_MENU => updatePauseMenu(&gs),
            .PLAY => {
                if (gs.round_state.last_mode != gs.round_state.mode) {
                    gs.round_state.mode_change_t = gs.t;
                    gs.round_state.last_mode = gs.round_state.mode;
                }

                try switch (gs.round_state.mode) {
                    .ROUND_START => updateStart(&gs),
                    .ROUND_PLAY => updatePlay(&gs),
                    .ROUND_SCORE => updateScore(&gs),
                    .ROUND_END => updateEnd(&gs),
                };

                if (gs.round_state.mode != gs.round_state.last_mode) {
                    continue; // Mode just changed, skip render
                }
            },
        };

        // Render
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.beginTextureMode(game_tex);
        rl.clearBackground(.black);

        try switch (gs.mode) {
            .MAIN_MENU => renderMainMenu(&gs),
            .PAUSE_MENU => renderPauseMenu(&gs),
            .PLAY => try switch (gs.round_state.mode) {
                .ROUND_START => renderStart(&gs),
                .ROUND_PLAY => renderPlay(&gs),
                .ROUND_SCORE => renderScore(&gs),
                .ROUND_END => renderEnd(&gs),
            },
        };

        rl.endTextureMode();

        rl.clearBackground(.black);
        rl.drawTexturePro(game_tex.texture, game_tex_rec, gs.screen_rect, rl.Vector2.zero(), 0.0, .white);
    }
}

fn updateMainMenu(gs: *GameState) !void {
    gs.round_state.mode = .ROUND_START;
    gs.mode = .PLAY;
}
fn renderMainMenu(gs: *GameState) !void {
    _ = gs;
}

fn updatePauseMenu(gs: *GameState) !void {
    _ = gs;
}
fn renderPauseMenu(gs: *GameState) !void {
    _ = gs;
}

fn updateStart(gs: *GameState) !void {
    gs.round_state.p1.rect.y = (gs.arena_rect.y + gs.arena_rect.height - gs.round_state.p1.rect.height) / 2;
    gs.round_state.p1.speed = gs.settings.p_base_speed;

    gs.round_state.p2.rect.y = (gs.arena_rect.y + gs.arena_rect.height - gs.round_state.p2.rect.height) / 2;
    gs.round_state.p2.speed = gs.settings.p_base_speed;

    gs.round_state.hit_count = 0;

    gs.round_state.ball.rect.x = (gs.arena_rect.x + gs.arena_rect.width - gs.round_state.ball.rect.width) / 2;
    gs.round_state.ball.rect.y = (gs.arena_rect.y + gs.arena_rect.height - gs.round_state.ball.rect.height) / 2;
    gs.round_state.ball.direction = rl.Vector2.zero();
    gs.round_state.ball.speed = 0;

    if ((gs.t - gs.round_state.mode_change_t) >= 1.5) {
        const x: f32 = 1 - (@as(f32, @floatFromInt(random.intRangeAtMost(i32, 0, 1))) * 2);
        const y: f32 = 1 - (@as(f32, @floatFromInt(random.intRangeAtMost(i32, 0, 1))) * 2);
        gs.round_state.ball.direction = .{ .x = x, .y = y };
        gs.round_state.ball.direction = gs.round_state.ball.direction.normalize();
        gs.round_state.ball.speed = gs.round_state.ball.rect.width * 15;
        gs.round_state.mode = .ROUND_PLAY;
    }
}
fn renderStart(gs: *GameState) !void {
    drawArena(gs);

    // P1
    rl.drawRectangleRec(gs.round_state.p1.rect, .white);
    // P2
    rl.drawRectangleRec(gs.round_state.p2.rect, .white);

    // Ball
    rl.drawRectangleRec(gs.round_state.ball.rect, .white);

    const t_left: i32 = @min(@as(i32, @intFromFloat(4 - ((gs.t - gs.round_state.mode_change_t) * 2))), 3);
    var buf: [3]u8 = undefined;
    const t_left_txt = try std.fmt.bufPrintZ(&buf, "{}", .{t_left});
    const t_left_txt_size = rl.measureTextEx(try rl.getFontDefault(), t_left_txt, 16, 1);
    rl.drawText(t_left_txt, @intFromFloat((gs.arena_rect.x + gs.arena_rect.width - t_left_txt_size.x) / 2), @intFromFloat((gs.arena_rect.y + gs.arena_rect.height - t_left_txt_size.y) / 4), 16, .white);
}

fn updatePlay(gs: *GameState) !void {
    if (rl.isKeyDown(rl.KeyboardKey.down)) {
        gs.round_state.p1.rect.y += gs.dt * gs.round_state.p1.speed * gs.round_state.p1.rect.height;
    } else if (rl.isKeyDown(rl.KeyboardKey.up)) {
        gs.round_state.p1.rect.y -= gs.dt * gs.round_state.p1.speed * gs.round_state.p1.rect.height;
    }

    gs.round_state.p1.rect.y = math.clamp(gs.round_state.p1.rect.y, gs.arena_rect.y, (gs.arena_rect.y + gs.arena_rect.height) - gs.round_state.p1.rect.height);

    if (gs.round_state.p1.rect.y == gs.arena_rect.y or gs.round_state.p1.rect.y == (gs.arena_rect.y + gs.arena_rect.height)) {
        if (!gs.round_state.p1.collided) {
            rl.playSound(gs.sounds.high_hit);
        }
        gs.round_state.p1.collided = true;
    } else {
        gs.round_state.p1.collided = false;
    }

    if (rl.isKeyDown(rl.KeyboardKey.s)) {
        gs.round_state.p2.rect.y += gs.dt * gs.round_state.p2.speed * gs.round_state.p2.rect.height;
    } else if (rl.isKeyDown(rl.KeyboardKey.w)) {
        gs.round_state.p2.rect.y -= gs.dt * gs.round_state.p2.speed * gs.round_state.p2.rect.height;
    }

    gs.round_state.p2.rect.y = math.clamp(gs.round_state.p2.rect.y, gs.arena_rect.y, (gs.arena_rect.y + gs.arena_rect.height) - gs.round_state.p2.rect.height);

    if (gs.round_state.p2.rect.y == gs.arena_rect.y or gs.round_state.p2.rect.y == (gs.arena_rect.y + gs.arena_rect.height)) {
        if (!gs.round_state.p2.collided) {
            rl.playSound(gs.sounds.high_hit);
        }
        gs.round_state.p2.collided = true;
    } else {
        gs.round_state.p2.collided = false;
    }

    const vel = gs.round_state.ball.direction.scale(gs.round_state.ball.speed);
    gs.round_state.ball.rect.x += (vel.x * gs.dt);
    gs.round_state.ball.rect.y += (vel.y * gs.dt);

    gs.round_state.ball.rect.y = math.clamp(gs.round_state.ball.rect.y, gs.arena_rect.y, (gs.arena_rect.y + gs.arena_rect.height) - gs.round_state.ball.rect.height);

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
    } else if (gs.round_state.ball.rect.y == gs.arena_rect.y or gs.round_state.ball.rect.y == ((gs.arena_rect.y + gs.arena_rect.height) - gs.round_state.ball.rect.height)) {
        gs.round_state.ball.collided = true;
        gs.round_state.ball.direction.y *= -1;
    } else {
        gs.round_state.ball.collided = false;
    }

    if (!already_collided and gs.round_state.ball.collided) {
        rl.setSoundPitch(gs.sounds.hit[0], 1.0 + (0.05 * @as(f32, @floatFromInt(gs.round_state.hit_count))));
        rl.playSound(gs.sounds.hit[0]);
    }

    if (gs.round_state.ball.rect.x <= gs.arena_rect.x or gs.round_state.ball.rect.x >= (gs.arena_rect.x + gs.arena_rect.width)) {
        // Goal!
        if (gs.round_state.ball.rect.x <= gs.arena_rect.x) {
            gs.round_state.p2.score += 1;
        } else {
            gs.round_state.p1.score += 1;
        }

        if (gs.round_state.p1.score >= 10 or gs.round_state.p2.score >= 10) {
            rl.playSound(gs.sounds.decay_white);
            gs.round_state.mode = .ROUND_END;
        } else {
            rl.playSound(gs.sounds.white[0]);
            gs.round_state.mode = .ROUND_SCORE;
        }
    }
}
fn renderPlay(gs: *GameState) !void {
    drawArena(gs);

    // P1
    rl.drawRectangleRec(gs.round_state.p1.rect, .white);
    // P2
    rl.drawRectangleRec(gs.round_state.p2.rect, .white);

    // Ball
    rl.drawRectangleRec(gs.round_state.ball.rect, .white);
}

fn drawArena(gs: *GameState) void {
    // Arena
    rl.drawRectangleRec(.{
        .x = gs.arena_rect.x,
        .y = gs.arena_rect.y - @as(f32, @floatFromInt(gs.settings.border_w)),
        .width = gs.arena_rect.width,
        .height = @as(f32, @floatFromInt(gs.settings.border_w)),
    }, .white);
    rl.drawRectangleRec(.{
        .x = gs.arena_rect.x,
        .y = gs.arena_rect.y + gs.arena_rect.height,
        .width = gs.arena_rect.width,
        .height = @as(f32, @floatFromInt(gs.settings.border_w)),
    }, .white);

    var i: f32 = 0;
    const max_i: f32 = @floatFromInt(@divFloor(gs.settings.win_h, (gs.settings.border_w * 2)) - 2);
    while (i < max_i) {
        rl.drawRectangleRec(.{
            .x = (gs.arena_rect.x + gs.arena_rect.width - @as(f32, @floatFromInt(gs.settings.border_w))) / 2,
            .y = gs.arena_rect.y + @as(f32, @floatFromInt(gs.settings.border_w)) * 2 * ((i + 1) - 0.75),
            .width = @as(f32, @floatFromInt(gs.settings.border_w)),
            .height = @as(f32, @floatFromInt(gs.settings.border_w)),
        }, rl.Color.alpha(.white, 0.1));
        i += 1;
    }
}

fn updateScore(gs: *GameState) !void {
    if ((gs.t - gs.round_state.mode_change_t) >= 2) {
        gs.round_state.mode = .ROUND_START;
    }
}
fn renderScore(gs: *GameState) !void {
    drawArena(gs);

    var buf: [3]u8 = undefined;
    const p1_score_txt = try std.fmt.bufPrintZ(&buf, "{}", .{gs.round_state.p1.score});
    const p1_score_txt_size = rl.measureTextEx(try rl.getFontDefault(), p1_score_txt, 16, 1);
    rl.drawText(p1_score_txt, @intFromFloat((gs.arena_rect.x + gs.arena_rect.width - p1_score_txt_size.x) / 4), @intFromFloat((gs.arena_rect.y + gs.arena_rect.height - p1_score_txt_size.y) / 4), 16, .white);
    const p2_score_txt = try std.fmt.bufPrintZ(&buf, "{}", .{gs.round_state.p2.score});
    const p2_score_txt_size = rl.measureTextEx(try rl.getFontDefault(), p2_score_txt, 16, 1);
    rl.drawText(p2_score_txt, @intFromFloat((gs.arena_rect.x + gs.arena_rect.width - p2_score_txt_size.x) / 4 * 3), @intFromFloat((gs.arena_rect.y + gs.arena_rect.height - p2_score_txt_size.y) / 4), 16, .white);
}

fn updateEnd(gs: *GameState) !void {
    _ = gs;
}
fn renderEnd(gs: *GameState) !void {
    _ = gs;
    rl.drawText("END", 0, 0, 16, .white);
}
