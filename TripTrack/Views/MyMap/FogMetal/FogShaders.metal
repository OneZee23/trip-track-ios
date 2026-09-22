#include <metal_stdlib>
using namespace metal;

// Спайк «метал-туман». Два прохода: покрытие открытого в r8Unorm и композит
// мглы на экран. Формы должны совпадать байт в байт с `FogUniforms` и
// `FogComposite` в `FogMetalVeil.swift`.

struct FogSegment {
    float2 p0;
    float2 p1;
};

struct FogUniforms {
    // Столбцы матрицы «смещение в точках карты → точки экрана»: (x,y) и (z,w).
    float4 m;
    // Экранное положение угла куска.
    float2 translation;
    // Размер вида в ТОЧКАХ (не пикселях) — в них же считаются ширины.
    float2 viewport;
    float halfWidth;
    float feather;
};

struct FogComposite {
    float4 colour;
    float alpha;
};

struct CoverageVertex {
    float4 position [[position]];
    float2 s0;
    float2 s1;
    float2 screen;
};

// Одна инстанция на отрезок, четыре вершины полосой. Прямоугольник строится в
// ЭКРАННЫХ точках: так его толщина не зависит от масштаба карты, а капсула во
// фрагменте меряется теми же числами.
vertex CoverageVertex fog_coverage_vertex(uint vid [[vertex_id]],
                                          uint iid [[instance_id]],
                                          const device FogSegment *segments [[buffer(0)]],
                                          constant FogUniforms &u [[buffer(1)]])
{
    FogSegment seg = segments[iid];
    float2x2 m = float2x2(float2(u.m.x, u.m.y), float2(u.m.z, u.m.w));
    float2 s0 = u.translation + m * seg.p0;
    float2 s1 = u.translation + m * seg.p1;

    float2 delta = s1 - s0;
    float len = length(delta);
    // Вырожденный отрезок (две одинаковые точки после проекции) — направление
    // берётся любое: капсула всё равно выйдет кругом.
    float2 dir = len > 1e-5 ? delta / len : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);
    float extend = u.halfWidth + u.feather;

    float2 base = (vid < 2) ? (s0 - dir * extend) : (s1 + dir * extend);
    float side = (vid & 1) == 0 ? -1.0 : 1.0;
    float2 screen = base + normal * side * extend;

    CoverageVertex out;
    out.position = float4(screen.x / u.viewport.x * 2.0 - 1.0,
                          1.0 - screen.y / u.viewport.y * 2.0,
                          0.0, 1.0);
    out.s0 = s0;
    out.s1 = s1;
    out.screen = screen;
    return out;
}

// Расстояние до отрезка (SDF капсулы) и перьевой спад. Смешивание стоит на
// `max`, поэтому стык двух соседних отрезков не даёт ни бусины, ни кольца:
// перекрытие берёт большее, а не складывает альфы.
fragment half fog_coverage_fragment(CoverageVertex in [[stage_in]],
                                    constant FogUniforms &u [[buffer(0)]])
{
    float2 pa = in.screen - in.s0;
    float2 ba = in.s1 - in.s0;
    float bb = dot(ba, ba);
    float h = bb > 1e-6 ? clamp(dot(pa, ba) / bb, 0.0, 1.0) : 0.0;
    float d = length(pa - ba * h);
    float coverage = 1.0 - smoothstep(u.halfWidth - u.feather, u.halfWidth, d);
    return half(coverage);
}

struct FullscreenVertex {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenVertex fog_composite_vertex(uint vid [[vertex_id]])
{
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenVertex out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

// Мгла с премультиплицированной альфой: открытое вычитается из неё покрытием.
// Ровный цвет нарочно — спайк отвечает на вопрос про движение, а не про
// облака и рампу.
fragment half4 fog_composite_fragment(FullscreenVertex in [[stage_in]],
                                      texture2d<half> coverage [[texture(0)]],
                                      constant FogComposite &c [[buffer(0)]])
{
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    half cov = coverage.sample(nearest, in.uv).r;
    half a = half(c.alpha) * (1.0h - cov);
    return half4(half3(c.colour.xyz) * a, a);
}
