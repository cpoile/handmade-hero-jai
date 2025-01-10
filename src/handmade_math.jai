//
// Vector math
//

operator + :: (a: Vector2, k: float) -> Vector2 #symmetric {
    return .{a.x+k, a.y+k};
}

operator - :: (a: Vector2, k: float) -> Vector2 {
    return .{a.x-k, a.y-k};
}
