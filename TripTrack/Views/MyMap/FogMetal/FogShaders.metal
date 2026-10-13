#include <metal_stdlib>
using namespace metal;

// Туман «Атласа». Два прохода: покрытие открытого в r8Unorm и композит
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

// Окно под подписью Apple Maps: коробка в ТОЧКАХ вида, радиус скругления,
// ширина спада и пол — во сколько раз мгла слабее в его середине. `enabled`
// нулём значит «окна нет»: композит тогда не трогает альфу вовсе.
struct FogCarve {
    float4 rect;
    float corner;
    float feather;
    float floor;
    float enabled;
};

// Прорезь у машины на живой записи: середина в ТОЧКАХ вида, радиус в них же и
// доля радиуса, открытая полностью. Нулевой радиус значит «прорези нет»:
// композит тогда не трогает альфу вовсе.
struct FogReveal {
    float2 centre;
    float radius;
    float solid;
};

// Сетка «Клеток» — третьего стиля карты. `side` нулём значит «сетки нет»:
// композит тогда берёт покрытие как есть, и кадр выходит байт в байт таким
// же, как у эталонного «Тумана». `m` — прямая матрица «смещение в точках
// карты → точки экрана», `inv` — обратная ей, `origin` — экранный угол
// прямоугольника кадра.
struct FogGrid {
    float4 m;
    float4 inv;
    float2 origin;
    // Начало мировой сетки — смещение ближайшей её границы от угла кадра, в
    // точках карты. Считает его CPU в double: без этого клетки считались бы
    // от угла кадра и ехали бы вместе с картой.
    float2 cellOrigin;
    float side;
};

struct FogComposite {
    float4 colour;
    float alpha;
    float2 viewport;
    FogCarve carve;
    FogReveal reveal;
    FogGrid grid;
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

// Расстояние до скруглённого прямоугольника: внутри отрицательное, снаружи —
// сколько точек до его кромки. `halfExtent` (а не `half`, как просилось по
// смыслу) — `half` в Metal занято под тип.
static float fog_sd_rounded_rect(float2 p, float2 centre, float2 halfExtent, float r)
{
    float2 q = abs(p - centre) - (halfExtent - r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Мгла с премультиплицированной альфой: открытое вычитается из неё покрытием.
// Ровный цвет нарочно: решение владельца 22 сентября — мгла на «Атласе»
// однотонная, без облаков и рампы глубины. Те остались в растровой кисти
// ради карты поездки и экрана записи.
//
// Сверх этого мгла знает ровно две вещи, и обе не про картинку тумана. Окно
// под подписью Apple: оно не снимает мглу, а ПРИГЛУШАЕТ до `floor` её силы, и
// спад наружу непрерывный — ступени давали эффект Маха, то есть вторую кромку
// вокруг мягкого пятна (задача A, 20 сентября, у растровой маски). И прорезь у
// машины на живой записи: у растра она маска на слое, потому что перерисовать
// его шестьдесят раз в секунду нельзя, — здесь же кадр и так рисуется заново,
// и дыра стоит двух умножений.
// Покрытие клетками: клетка открыта ЦЕЛИКОМ или закрыта целиком.
//
// Снимается покрытие в ПЯТИ точках клетки — в середине и по четырём
// направлениям от неё, — и берётся большее. Одной середины мало: коридор
// шириной в клетку легко проходит мимо её центра, и клетка, по которой
// человек проехал, осталась бы закрытой. Порог низкий по той же причине —
// «задело» важнее, чем «накрыло»: слой открытого (`RevealGrid`) отмечает
// ячейку, через которую трек ПРОШЁЛ, и клетки обязаны показывать то же.
static half fog_cell_coverage(texture2d<half> coverage, sampler s,
                              constant FogComposite &c, float2 p)
{
    float2x2 fwd = float2x2(float2(c.grid.m.x, c.grid.m.y), float2(c.grid.m.z, c.grid.m.w));
    float2x2 inv = float2x2(float2(c.grid.inv.x, c.grid.inv.y), float2(c.grid.inv.z, c.grid.inv.w));

    // Смещение от угла кадра в точках карты — в Float32 оно небольшое, а вот
    // абсолютная координата у Краснодара это ~1.6e8, и считать индекс клетки
    // по ней значило бы вернуть дрожь, от которой куски меша и придуманы.
    float2 mp = inv * (p - c.grid.origin);
    float2 fromGrid = mp - c.grid.cellOrigin;
    float2 centreMp = (floor(fromGrid / c.grid.side) + 0.5) * c.grid.side + c.grid.cellOrigin;
    float2 centre = c.grid.origin + fwd * centreMp;
    // Клетка на экране это параллелограмм, а не квадрат: карту можно
    // повернуть. Шаги берутся из ТОЙ ЖЕ матрицы, поэтому пробы остаются
    // внутри клетки при любом повороте.
    float2 ex = (fwd * float2(c.grid.side, 0.0)) * 0.3;
    float2 ey = (fwd * float2(0.0, c.grid.side)) * 0.3;

    half hit = coverage.sample(s, centre / c.viewport).r;
    hit = max(hit, coverage.sample(s, (centre + ex) / c.viewport).r);
    hit = max(hit, coverage.sample(s, (centre - ex) / c.viewport).r);
    hit = max(hit, coverage.sample(s, (centre + ey) / c.viewport).r);
    hit = max(hit, coverage.sample(s, (centre - ey) / c.viewport).r);
    return hit > 0.35h ? 1.0h : 0.0h;
}

fragment half4 fog_composite_fragment(FullscreenVertex in [[stage_in]],
                                      texture2d<half> coverage [[texture(0)]],
                                      constant FogComposite &c [[buffer(0)]])
{
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    float2 p = in.uv * c.viewport;
    half cov = c.grid.side > 0.0
        ? fog_cell_coverage(coverage, nearest, c, p)
        : coverage.sample(nearest, in.uv).r;
    half a = half(c.alpha) * (1.0h - cov);
    if (c.carve.enabled > 0.5) {
        float2 halfExtent = c.carve.rect.zw * 0.5;
        float d = fog_sd_rounded_rect(p, c.carve.rect.xy + halfExtent, halfExtent,
                                      c.carve.corner);
        // Нулевое перо дало бы деление на ноль; у окна атрибуции оно шесть
        // точек, но шейдер не обязан верить зовущему на слово.
        float w = 1.0 - smoothstep(0.0, max(c.carve.feather, 1e-3), d);
        a *= half(1.0 - (1.0 - c.carve.floor) * w);
    }
    if (c.reveal.radius > 0.0) {
        // Спад ЛИНЕЙНЫЙ, а не `smoothstep`: у кисти растра это радиальный
        // градиент с остановками 0, `solid`, 1 (`FogVeilPainter.punchReveal`),
        // а у маски вуали — тот же `CAGradientLayer`. Три прорези обязаны
        // выглядеть одинаково: человек видит их в одну и ту же секунду, когда
        // карта откатывается на растр.
        float d = distance(p, c.reveal.centre) / c.reveal.radius;
        float keep = clamp((d - c.reveal.solid) / max(1.0 - c.reveal.solid, 1e-3), 0.0, 1.0);
        a *= half(keep);
    }
    return half4(half3(c.colour.xyz) * a, a);
}
