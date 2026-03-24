import { useState, useEffect, useRef } from "react";

// ═══════════════════════════════════════════════════
// ROAD TRIP TRACKER v4
// Strava/Drive2-inspired clean functional design
// Pixel accents only: logo, badges, achievements
// Liquid Glass: floating tab bar, profile header
// ═══════════════════════════════════════════════════

const PX = `'Press Start 2P', monospace`;
const UI = `'DM Sans', -apple-system, BlinkMacSystemFont, sans-serif`;

const C = {
  dark: {
    bg: "#000000",
    card: "#1C1C1E",
    cardAlt: "#2C2C2E",
    border: "rgba(255,255,255,0.08)",
    text: "#FFFFFF",
    t2: "rgba(255,255,255,0.6)",
    t3: "rgba(255,255,255,0.3)",
    accent: "#FC4C02", // Strava orange
    accentBg: "rgba(252,76,2,0.1)",
    green: "#34C759",
    greenBg: "rgba(52,199,89,0.1)",
    blue: "#007AFF",
    blueBg: "rgba(0,122,255,0.1)",
    red: "#FF3B30",
    yellow: "#FFD60A",
    // Liquid Glass
    glass: "rgba(44,44,46,0.72)",
    glassBorder: "rgba(255,255,255,0.18)",
    glassBlur: "blur(40px) saturate(180%)",
    glassShine: "linear-gradient(180deg, rgba(255,255,255,0.12) 0%, rgba(255,255,255,0) 60%)",
    glassShadow: "0 8px 32px rgba(0,0,0,0.4)",
    fog: "rgba(0,0,0,0.7)",
    mapBg: "#1a1f2e",
  },
  light: {
    bg: "#F2F2F7",
    card: "#FFFFFF",
    cardAlt: "#F5F5F7",
    border: "rgba(0,0,0,0.06)",
    text: "#000000",
    t2: "rgba(0,0,0,0.55)",
    t3: "rgba(0,0,0,0.25)",
    accent: "#FC4C02",
    accentBg: "rgba(252,76,2,0.08)",
    green: "#34C759",
    greenBg: "rgba(52,199,89,0.08)",
    blue: "#007AFF",
    blueBg: "rgba(0,122,255,0.08)",
    red: "#FF3B30",
    yellow: "#FFD60A",
    glass: "rgba(255,255,255,0.72)",
    glassBorder: "rgba(255,255,255,0.8)",
    glassBlur: "blur(40px) saturate(180%)",
    glassShine: "linear-gradient(180deg, rgba(255,255,255,0.6) 0%, rgba(255,255,255,0) 60%)",
    glassShadow: "0 8px 32px rgba(0,0,0,0.08)",
    fog: "rgba(200,200,200,0.6)",
    mapBg: "#e8eaee",
  },
};

// ── Simple line icons ─────────────────────────────
const I = {
  route: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><circle cx="6" cy="19" r="3"/><circle cx="18" cy="5" r="3"/><path d="M6 16V8a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v8"/></svg>,
  clock: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>,
  speed: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M12 12l3.5-3.5"/><circle cx="12" cy="12" r="10"/></svg>,
  fuel: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M3 22V6a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16"/><path d="M13 10h2a2 2 0 0 1 2 2v3a2 2 0 0 0 4 0V9l-3-3"/><path d="M5 14h8"/></svg>,
  camera: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>,
  user: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>,
  chart: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M18 20V10M12 20V4M6 20v-6"/></svg>,
  filter: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M22 3H2l8 9.46V19l4 2v-8.54z"/></svg>,
  back: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>,
  car: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M5 17h14M6 17V9.5L7.5 6h9L18 9.5V17"/><circle cx="8" cy="17" r="1"/><circle cx="16" cy="17" r="1"/></svg>,
  map: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M1 6v16l7-4 8 4 7-4V2l-7 4-8-4-7 4z"/><path d="M8 2v16M16 6v16"/></svg>,
  flag: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><path d="M4 22v-7"/></svg>,
  lock: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>,
  check: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5" strokeLinecap="round"><path d="M20 6L9 17l-5-5"/></svg>,
  x: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>,
  sun: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M16.36 16.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M16.36 7.64l1.42-1.42"/></svg>,
  moon: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>,
  globe: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10A15.3 15.3 0 0 1 12 2z"/></svg>,
  play: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill={c}><polygon points="5,3 19,12 5,21"/></svg>,
  pause: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill={c}><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>,
  stop: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill={c}><rect x="4" y="4" width="16" height="16" rx="3"/></svg>,
  calendar: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>,
  locationArrow: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M12 2v8M12 2L8 6M12 2l4 4"/><circle cx="12" cy="12" r="3"/></svg>,
  locationArrowFilled: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill={c} stroke={c} strokeWidth="1.5"><path d="M12 2v8l4-4-4-4z"/><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor"/></svg>,
  compass: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="10"/><path d="M16 8l-4 8-4-8 8-4z"/></svg>,
  plus: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>,
  minus: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M5 12h14"/></svg>,
  chevronDown: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M6 9l6 6 6-6"/></svg>,
  chevronUp: (c, s = 20) => <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round"><path d="M18 15l-6-6-6 6"/></svg>,
};

// ── Mock Data ───────────────────────────────────
const TRIPS = [
  { id: 1, date: "28 фев", dateFull: "2026-02-28", region: "Краснодарский край", distance: 142.3, duration: "2ч 15м", durationMin: 135, fuel: 11.2, title: "Горячий Ключ → Джубга", desc: "Серпантин через перевал, остановка у водопадов", photos: 4, avgSpeed: 63, maxSpeed: 112, elevation: 840, car: "VW Polo 2018" },
  { id: 2, date: "20 фев", dateFull: "2026-02-20", region: "Адыгея", distance: 89.7, duration: "1ч 30м", durationMin: 90, fuel: 7.1, title: "Краснодар → Лаго-Наки", desc: "Поднялись на плато, снег ещё лежит", photos: 7, avgSpeed: 58, maxSpeed: 95, elevation: 1680, car: "VW Polo 2018" },
  { id: 3, date: "14 фев", dateFull: "2026-02-14", region: "Краснодарский край", distance: 298.5, duration: "4ч 40м", durationMin: 280, fuel: 23.4, title: "Краснодар → Сочи", desc: "Дневной трип до Сочи, пробки в Туапсе", photos: 12, avgSpeed: 64, maxSpeed: 130, elevation: 420, car: "VW Polo 2018" },
  { id: 4, date: "25 янв", dateFull: "2026-01-25", region: "Ростовская область", distance: 275.0, duration: "3ч 20м", durationMin: 200, fuel: 21.0, title: "Краснодар → Ростов-на-Дону", desc: "M4 как стрела", photos: 2, avgSpeed: 82, maxSpeed: 145, elevation: 65, car: "VW Polo 2018" },
  { id: 5, date: "10 янв", dateFull: "2026-01-10", region: "Краснодарский край", distance: 45.2, duration: "0ч 50м", durationMin: 50, fuel: 3.8, title: "По городу: ТО + мойка", desc: "Плановое ТО у дилера", photos: 0, avgSpeed: 32, maxSpeed: 75, elevation: 12, car: "VW Polo 2018" },
  { id: 6, date: "5 мар", dateFull: "2026-03-05", region: "Краснодарский край", distance: 67.8, duration: "1ч 10м", durationMin: 70, fuel: 5.4, title: "Краснодар → Горячий Ключ", desc: "Быстрая вылазка на выходных", photos: 3, avgSpeed: 58, maxSpeed: 98, elevation: 320, car: "VW Polo 2018" },
  { id: 7, date: "11 мар", dateFull: "2026-03-11", region: "Адыгея", distance: 156.2, duration: "2ч 40м", durationMin: 160, fuel: 12.5, title: "Краснодар → Гуамское ущелье", desc: "Наконец добрался до ущелья, виды бомба", photos: 9, avgSpeed: 59, maxSpeed: 105, elevation: 950, car: "VW Polo 2018" },
];

const REGIONS = [
  { id: "krd", name: "Краснодарский край", trips: 4, unlocked: true },
  { id: "ady", name: "Адыгея", trips: 2, unlocked: true },
  { id: "ros", name: "Ростовская обл.", trips: 1, unlocked: true },
  { id: "crm", name: "Крым", trips: 0, unlocked: false },
  { id: "stv", name: "Ставропольский кр.", trips: 0, unlocked: false },
  { id: "vlg", name: "Волгоградская обл.", trips: 0, unlocked: false },
  { id: "vrn", name: "Воронежская обл.", trips: 0, unlocked: false },
  { id: "dag", name: "Дагестан", trips: 0, unlocked: false },
  { id: "klm", name: "Калмыкия", trips: 0, unlocked: false },
];

const AVATARS = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🏁", "🗺️", "⛽"];

const L = {
  ru: { feed: "Лента", record: "Запись", regions: "Регионы", profile: "Профиль", stats: "Статистика", filters: "Фильтры", km: "км", trips: "поездок", time: "в пути", avg: "ср. скор.", fuel: "топливо", cost: "расход", back: "Назад", start: "Начать поездку", noTrips: "Пока нет поездок", goRide: "Нажмите Запись чтобы начать", unlocked: "открыто", locked: "Заблокировано", view: "Смотреть", apply: "Применить", reset: "Сбросить", resetSecondary: "Сбросить вторичные", all: "Все", week: "Неделя", month: "Месяц", year: "Год", total: "Всё время", theme: "Тема", lang: "Язык", dark: "Тёмная", light: "Светлая", garage: "Гараж", about: "О приложении", author: "Автор", photos: "фото", calendar: "Календарь", consumption: "Расход л/100км", priceL: "₽ за литр", dateFrom: "Дата от", dateTo: "Дата до", distFrom: "Км от", distTo: "Км до", region: "Регион", maxSpeed: "макс.", elevation: "набор высоты", explored: "исследовано", fogOfWar: "Карта открытий", recording: "Запись идёт", paused: "Пауза" },
  en: { feed: "Feed", record: "Record", regions: "Regions", profile: "Profile", stats: "Stats", filters: "Filters", km: "km", trips: "trips", time: "drive time", avg: "avg speed", fuel: "fuel", cost: "fuel cost", back: "Back", start: "Start trip", noTrips: "No trips yet", goRide: "Tap Record to start", unlocked: "unlocked", locked: "Locked", view: "View", apply: "Apply", reset: "Reset", resetSecondary: "Reset secondary", all: "All", week: "Week", month: "Month", year: "Year", total: "All time", theme: "Theme", lang: "Language", dark: "Dark", light: "Light", garage: "Garage", about: "About", author: "Author", photos: "photos", calendar: "Calendar", consumption: "L/100km", priceL: "$/L", dateFrom: "From", dateTo: "To", distFrom: "Km from", distTo: "Km to", region: "Region", maxSpeed: "max", elevation: "elevation", explored: "explored", fogOfWar: "Discovery Map", recording: "Recording", paused: "Paused" },
};

// ── Only pixel element: achievement badge ────────
const Badge = ({ children, color = "#FC4C02" }) => (
  <span style={{ fontFamily: PX, fontSize: 7, color, background: color + "15", padding: "3px 8px", borderRadius: 6, letterSpacing: 0.5, display: "inline-flex", alignItems: "center", gap: 4 }}>
    {children}
  </span>
);

// ── Card ─────────────────────────────────────────
const Card = ({ children, style, onClick, c }) => (
  <div onClick={onClick} style={{
    background: c.card, borderRadius: 16, padding: 16,
    cursor: onClick ? "pointer" : "default",
    transition: "all 0.2s ease", ...style,
  }}>{children}</div>
);

// ── Chip ─────────────────────────────────────────
const Chip = ({ children, active, onClick, c, style }) => (
  <button onClick={onClick} style={{
    background: active ? c.accent : c.card,
    border: "none", borderRadius: 20, padding: "8px 16px",
    color: active ? "#fff" : c.t2,
    fontSize: 13, fontFamily: UI, fontWeight: 600, cursor: "pointer",
    transition: "all 0.2s", outline: "none", whiteSpace: "nowrap", ...style,
  }}>{children}</button>
);

// ═══════════════════════════════════════
// TRIP CARD — Strava-style activity card
// ═══════════════════════════════════════

const TripCard = ({ trip, c, l, i }) => {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ opacity: 0, animation: `fadeUp .35s ease ${i * 0.05}s forwards` }}>
      <Card c={c} onClick={() => setOpen(!open)} style={{ marginBottom: 8 }}>
        {/* Top: avatar + name + date */}
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 12 }}>
          <div style={{ width: 36, height: 36, borderRadius: 18, background: c.accentBg, display: "flex", alignItems: "center", justifyContent: "center" }}>
            {I.car(c.accent, 18)}
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: UI, fontSize: 14, fontWeight: 700, color: c.text }}>{trip.car}</div>
            <div style={{ fontFamily: UI, fontSize: 12, color: c.t3 }}>{trip.date} · {trip.region}</div>
          </div>
          {trip.photos > 0 && (
            <div style={{ display: "flex", alignItems: "center", gap: 4, color: c.t3 }}>
              {I.camera(c.t3, 14)}
              <span style={{ fontFamily: UI, fontSize: 12 }}>{trip.photos}</span>
            </div>
          )}
        </div>

        {/* Title */}
        <h3 style={{ fontFamily: UI, fontSize: 18, fontWeight: 800, color: c.text, margin: "0 0 12px", lineHeight: 1.3 }}>
          {trip.title}
        </h3>

        {/* Map placeholder — route preview */}
        <div style={{
          height: 80, borderRadius: 12, marginBottom: 12, overflow: "hidden", position: "relative",
          background: c === C.dark ? "#1a1f2e" : "#e8eaee",
        }}>
          <svg width="100%" height="100%" style={{ position: "absolute", inset: 0 }}>
            <path d={`M 20 60 Q 60 20 120 40 T 240 25 T 370 50`} stroke={c.accent} strokeWidth="3" fill="none" strokeLinecap="round" opacity="0.8" />
            <circle cx="20" cy="60" r="4" fill={c.green} />
            <circle cx="370" cy="50" r="4" fill={c.red} />
          </svg>
        </div>

        {/* Stats grid — Strava style */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 4 }}>
          {[
            { val: `${trip.distance}`, unit: " км", label: "Дистанция" },
            { val: trip.duration, unit: "", label: "Время" },
            { val: `${trip.avgSpeed}`, unit: " км/ч", label: "Ср. скорость" },
          ].map((s, j) => (
            <div key={j} style={{ padding: "8px 0" }}>
              <div style={{ fontFamily: UI, fontSize: 20, fontWeight: 800, color: c.text, lineHeight: 1 }}>
                {s.val}<span style={{ fontSize: 13, fontWeight: 600, color: c.t2 }}>{s.unit}</span>
              </div>
              <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, marginTop: 3 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* Secondary stats */}
        {open && (
          <div style={{ animation: "fadeIn .2s ease" }}>
            <div style={{ height: 1, background: c.border, margin: "12px 0" }} />
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 4, marginBottom: 12 }}>
              {[
                { val: `${trip.maxSpeed}`, unit: " км/ч", label: l.maxSpeed },
                { val: `${trip.fuel}`, unit: " л", label: l.fuel },
                { val: `${trip.elevation}`, unit: " м", label: l.elevation },
              ].map((s, j) => (
                <div key={j} style={{ padding: "8px 0" }}>
                  <div style={{ fontFamily: UI, fontSize: 18, fontWeight: 800, color: c.text, lineHeight: 1 }}>
                    {s.val}<span style={{ fontSize: 12, fontWeight: 600, color: c.t2 }}>{s.unit}</span>
                  </div>
                  <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, marginTop: 3 }}>{s.label}</div>
                </div>
              ))}
            </div>
            <p style={{ fontFamily: UI, fontSize: 14, color: c.t2, lineHeight: 1.5, margin: 0 }}>{trip.desc}</p>
          </div>
        )}
      </Card>
    </div>
  );
};

// ═══════════════════════════════════════
// CONTRIBUTION CALENDAR — Feed (collapsed week / expanded month)
// ═══════════════════════════════════════

const MONTH_NAMES_RU = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"];
const MONTH_NAMES_EN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const DOW_RU = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];
const DOW_EN = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

function getKmByDay(trips) {
  const byDay = {};
  trips.forEach(t => {
    const d = t.dateFull;
    if (!byDay[d]) byDay[d] = 0;
    byDay[d] += t.distance;
  });
  return byDay;
}

function getMaxKm(byDay) {
  return Math.max(0, ...Object.values(byDay));
}

function getWeekDates(anchorDate) {
  const d = new Date(anchorDate);
  const day = d.getDay();
  const mon = day === 0 ? 6 : day - 1;
  d.setDate(d.getDate() - mon);
  const out = [];
  for (let i = 0; i < 7; i++) {
    out.push(new Date(d));
    d.setDate(d.getDate() + 1);
  }
  return out;
}

function getMonthGrid(year, month) {
  const first = new Date(year, month, 1);
  const last = new Date(year, month + 1, 0);
  const startDay = first.getDay();
  const monOffset = startDay === 0 ? 6 : startDay - 1;
  const cells = [];
  for (let i = 0; i < monOffset; i++) cells.push(null);
  for (let d = 1; d <= last.getDate(); d++) cells.push({ day: d, dateStr: `${year}-${String(month + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}` });
  return cells;
}

const ContributionCalendar = ({ trips, selectedDate, onSelectDate, expanded, onToggleExpand, currentYear, currentMonth, onMonthChange, c, l, lang }) => {
  const byDay = getKmByDay(trips);
  const maxKm = getMaxKm(byDay);
  const monthNames = lang === "ru" ? MONTH_NAMES_RU : MONTH_NAMES_EN;
  const dow = lang === "ru" ? DOW_RU : DOW_EN;
  const today = new Date();
  const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;

  const intensity = (km) => {
    if (!km || maxKm === 0) return 0;
    const r = km / maxKm;
    if (r <= 1 / 3) return 0.15;
    if (r <= 2 / 3) return 0.4;
    return 0.9;
  };

  const weekDates = getWeekDates(today);
  const monthGrid = getMonthGrid(currentYear, currentMonth);
  const monthLabel = `${monthNames[currentMonth]} ${currentYear}`;

  return (
    <Card c={c} style={{ marginBottom: 10, padding: "12px 16px" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: expanded ? 12 : 8 }}>
        <span style={{ fontFamily: UI, fontSize: 15, fontWeight: 700, color: c.text }}>{l.calendar}</span>
        {expanded && <span style={{ fontFamily: UI, fontSize: 14, fontWeight: 600, color: c.t2 }}>{monthLabel}</span>}
        <button onClick={onToggleExpand} style={{ background: "none", border: "none", cursor: "pointer", padding: 4, display: "flex" }}>
          {expanded ? I.chevronUp(c.t2, 18) : I.chevronDown(c.t2, 18)}
        </button>
      </div>
      {!expanded && (
        <>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4, marginBottom: 4 }}>
            {dow.map(d => <div key={d} style={{ textAlign: "center", fontFamily: UI, fontSize: 12, color: c.t3, fontWeight: 600 }}>{d}</div>)}
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4 }}>
            {weekDates.map((d) => {
              const dateStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
              const km = byDay[dateStr] || 0;
              const isToday = dateStr === todayStr;
              const isSelected = selectedDate === dateStr;
              const op = intensity(km);
              return (
                <button
                  key={dateStr}
                  onClick={() => onSelectDate(km > 0 ? (selectedDate === dateStr ? null : dateStr) : null)}
                  style={{
                    aspectRatio: "1", borderRadius: 8, border: "2px solid transparent", display: "flex", alignItems: "center", justifyContent: "center",
                    background: op > 0 ? `${c.accent}` : c.cardAlt, opacity: op > 0 ? op : 1,
                    borderColor: isToday ? c.t3 : isSelected ? c.accent : "transparent",
                    cursor: "pointer", fontFamily: UI, fontSize: 12, fontWeight: 600, color: op > 0 ? "#fff" : c.t3,
                  }}
                >
                  {d.getDate()}
                </button>
              );
            })}
          </div>
        </>
      )}
      {expanded && (
        <>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
            <button onClick={() => onMonthChange(-1)} style={{ background: c.cardAlt, border: "none", borderRadius: 10, padding: "6px 10px", cursor: "pointer" }}>{I.chevronDown(c.t2, 16)}</button>
            <span style={{ fontFamily: UI, fontSize: 14, fontWeight: 700, color: c.text }}>{monthLabel}</span>
            <button onClick={() => onMonthChange(1)} style={{ background: c.cardAlt, border: "none", borderRadius: 10, padding: "6px 10px", cursor: "pointer", transform: "rotate(180deg)" }}>{I.chevronDown(c.t2, 16)}</button>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4, marginBottom: 4 }}>
            {dow.map(d => <div key={d} style={{ textAlign: "center", fontFamily: UI, fontSize: 12, color: c.t3, fontWeight: 600 }}>{d}</div>)}
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4 }}>
            {monthGrid.map((cell, i) => {
              if (!cell) return <div key={`e-${i}`} />;
              const km = byDay[cell.dateStr] || 0;
              const op = intensity(km);
              const isToday = cell.dateStr === todayStr;
              const isSelected = selectedDate === cell.dateStr;
              return (
                <button
                  key={cell.dateStr}
                  onClick={() => onSelectDate(km > 0 ? (selectedDate === cell.dateStr ? null : cell.dateStr) : null)}
                  style={{
                    aspectRatio: "1", borderRadius: 8, border: "2px solid transparent", display: "flex", alignItems: "center", justifyContent: "center",
                    background: op > 0 ? `${c.accent}` : c.cardAlt, opacity: op > 0 ? op : 1,
                    borderColor: isToday ? c.t3 : isSelected ? c.accent : "transparent",
                    cursor: "pointer", fontFamily: UI, fontSize: 12, fontWeight: 600, color: op > 0 ? "#fff" : c.t3,
                  }}
                >
                  {cell.day}
                </button>
              );
            })}
          </div>
        </>
      )}
    </Card>
  );
};

// ═══════════════════════════════════════
// FILTERS BOTTOM SHEET
// ═══════════════════════════════════════

const Filters = ({ show, onClose, filters, setF, c, l }) => {
  if (!show) return null;
  const regions = [...new Set(TRIPS.map(t => t.region))];
  const inp = { width: "100%", background: c.cardAlt, border: "none", borderRadius: 12, padding: "12px 14px", color: c.text, fontSize: 15, fontFamily: UI, outline: "none", boxSizing: "border-box" };
  const resetSecondary = () => setF(prev => ({ ...prev, region: null, distFrom: null, distTo: null }));

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 100, background: "rgba(0,0,0,0.4)", display: "flex", alignItems: "flex-end", justifyContent: "center", animation: "fadeIn .15s ease" }} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{ width: "100%", maxWidth: 420, background: c.card, borderRadius: "20px 20px 0 0", padding: "16px 16px 36px", animation: "slideUp .3s cubic-bezier(.32,.72,0,1)" }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: c.border, margin: "0 auto 16px" }} />
        <h3 style={{ fontFamily: UI, fontSize: 18, fontWeight: 800, color: c.text, margin: "0 0 16px" }}>{l.filters}</h3>

        <div style={{ fontFamily: UI, fontSize: 13, color: c.t2, fontWeight: 600, marginBottom: 8 }}>{l.region}</div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 18 }}>
          <Chip c={c} active={!filters.region} onClick={() => setF(f => ({ ...f, region: null }))}>{l.all}</Chip>
          {regions.map(r => <Chip key={r} c={c} active={filters.region === r} onClick={() => setF(f => ({ ...f, region: r }))}>{r}</Chip>)}
        </div>

        <div style={{ display: "flex", gap: 10, marginBottom: 14 }}>
          {[{ lbl: l.distFrom, k: "distFrom" }, { lbl: l.distTo, k: "distTo" }].map(f => (
            <div key={f.k} style={{ flex: 1 }}>
              <div style={{ fontFamily: UI, fontSize: 13, color: c.t2, fontWeight: 600, marginBottom: 6 }}>{f.lbl}</div>
              <input type="number" value={filters[f.k] || ""} onChange={e => setF(p => ({ ...p, [f.k]: e.target.value ? +e.target.value : null }))} placeholder="—" style={inp} />
            </div>
          ))}
        </div>

        <div style={{ display: "flex", gap: 10 }}>
          <button onClick={resetSecondary} style={{ flex: 1, background: c.cardAlt, border: "none", borderRadius: 14, padding: 14, color: c.t2, fontSize: 15, fontWeight: 700, fontFamily: UI, cursor: "pointer" }}>{l.resetSecondary}</button>
          <button onClick={onClose} style={{ flex: 2, background: c.accent, border: "none", borderRadius: 14, padding: 14, color: "#fff", fontSize: 15, fontWeight: 700, fontFamily: UI, cursor: "pointer" }}>{l.apply}</button>
        </div>
      </div>
    </div>
  );
};

// ═══════════════════════════════════════
// FEED
// ═══════════════════════════════════════

const FeedScreen = ({ c, l, lang, onProfile, onStats, regF, clearRegF }) => {
  const [showF, setShowF] = useState(false);
  const [calendarExpanded, setCalendarExpanded] = useState(false);
  const [selectedDate, setSelectedDate] = useState(null);
  const [calendarYear, setCalendarYear] = useState(() => new Date().getFullYear());
  const [calendarMonth, setCalendarMonth] = useState(() => new Date().getMonth());
  const [f, setF] = useState({ region: regF || null, distFrom: null, distTo: null, date: null });
  useEffect(() => { if (regF) setF(prev => ({ ...prev, region: regF })); }, [regF]);
  useEffect(() => { if (selectedDate) setF(prev => ({ ...prev, date: selectedDate })); else setF(prev => ({ ...prev, date: null })); }, [selectedDate]);

  const list = TRIPS.filter(t => {
    if (f.region && t.region !== f.region) return false;
    if (f.distFrom && t.distance < f.distFrom) return false;
    if (f.distTo && t.distance > f.distTo) return false;
    if (f.date && t.dateFull !== f.date) return false;
    return true;
  });
  const hasF = f.region !== null || f.distFrom !== null || f.distTo !== null || f.date !== null;
  const totKm = list.reduce((s, t) => s + t.distance, 0);
  const totMin = list.reduce((s, t) => s + t.durationMin, 0);

  const groupedByMonth = list.reduce((acc, t) => {
    const [y, m] = t.dateFull.split("-");
    const key = `${y}-${m}`;
    if (!acc[key]) acc[key] = [];
    acc[key].push(t);
    return acc;
  }, {});
  const monthOrder = Object.keys(groupedByMonth).sort((a, b) => b.localeCompare(a));
  const monthNames = lang === "ru" ? MONTH_NAMES_RU : MONTH_NAMES_EN;
  const formatDateChip = (dateStr) => {
    if (!dateStr) return "";
    const [y, m, d] = dateStr.split("-").map(Number);
    const monthShort = lang === "ru" ? MONTH_NAMES_RU[m - 1].slice(0, 3) : MONTH_NAMES_EN[m - 1].slice(0, 3);
    return `${d} ${monthShort}`;
  };

  return (
    <div style={{ padding: "0 16px 100px" }}>
      {/* Sticky header */}
      <div style={{ padding: "56px 0 12px", position: "sticky", top: 0, zIndex: 10, background: `linear-gradient(${c.bg} 80%, transparent)` }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <button onClick={onProfile} style={{ width: 38, height: 38, borderRadius: 19, background: c.card, border: "none", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            {I.user(c.t2, 18)}
          </button>
          <div style={{ textAlign: "center" }}>
            <span style={{ fontFamily: PX, fontSize: 10, color: c.accent, letterSpacing: 1 }}>ROAD TRIP</span>
            <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, fontWeight: 600, letterSpacing: 2, textTransform: "uppercase" }}>tracker</div>
          </div>
          <button onClick={onStats} style={{ width: 38, height: 38, borderRadius: 19, background: c.card, border: "none", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            {I.chart(c.t2, 18)}
          </button>
        </div>
      </div>

      {/* Contribution Calendar */}
      <ContributionCalendar
        trips={TRIPS}
        selectedDate={selectedDate}
        onSelectDate={setSelectedDate}
        expanded={calendarExpanded}
        onToggleExpand={() => setCalendarExpanded(!calendarExpanded)}
        currentYear={calendarYear}
        currentMonth={calendarMonth}
        onMonthChange={delta => {
          let m = calendarMonth + delta;
          let y = calendarYear;
          if (m > 11) { m = 0; y++; }
          if (m < 0) { m = 11; y--; }
          setCalendarMonth(m);
          setCalendarYear(y);
        }}
        c={c}
        l={l}
        lang={lang}
      />

      {/* Quick stats */}
      <Card c={c} style={{ marginBottom: 10, padding: "14px 16px" }}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", textAlign: "center" }}>
          {[
            { val: list.length, label: l.trips, color: c.accent },
            { val: `${totKm.toFixed(0)}`, label: l.km, color: c.text },
            { val: `${Math.floor(totMin / 60)}ч ${totMin % 60}м`, label: l.time, color: c.text },
          ].map((s, i) => (
            <div key={i}>
              <div style={{ fontFamily: UI, fontSize: 22, fontWeight: 800, color: s.color }}>{s.val}</div>
              <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, marginTop: 2 }}>{s.label}</div>
            </div>
          ))}
        </div>
      </Card>

      {/* Filter bar */}
      <div style={{ display: "flex", gap: 6, marginBottom: 12, flexWrap: "wrap" }}>
        <Chip c={c} active={hasF} onClick={() => setShowF(true)} style={{ display: "flex", alignItems: "center", gap: 6 }}>
          {I.filter(hasF ? "#fff" : c.t2, 14)} {l.filters}
        </Chip>
        {f.date && (
          <Chip c={c} active onClick={() => { setSelectedDate(null); }} style={{ display: "flex", alignItems: "center", gap: 4 }}>
            {formatDateChip(f.date)} {I.x("#fff", 12)}
          </Chip>
        )}
        {f.region && (
          <Chip c={c} active onClick={() => { setF(p => ({ ...p, region: null })); clearRegF?.(); }} style={{ display: "flex", alignItems: "center", gap: 4 }}>
            {f.region} {I.x("#fff", 12)}
          </Chip>
        )}
      </div>

      {/* Feed — grouped by month */}
      {list.length > 0 ? (
        <>
          {monthOrder.map(key => {
            const [y, m] = key.split("-");
            const monthLabel = `${monthNames[Number(m) - 1]} ${y}`;
            return (
              <div key={key} style={{ marginBottom: 16 }}>
                <div style={{ fontFamily: UI, fontSize: 13, fontWeight: 700, color: c.t3, marginBottom: 8 }}>{monthLabel}</div>
                {groupedByMonth[key].map((t, i) => <TripCard key={t.id} trip={t} c={c} l={l} i={i} />)}
              </div>
            );
          })}
        </>
      ) : (
        <div style={{ textAlign: "center", padding: "80px 20px" }}>
          {I.car(c.t3, 40)}
          <div style={{ fontFamily: UI, fontSize: 17, fontWeight: 700, color: c.t2, marginTop: 16 }}>{l.noTrips}</div>
          <div style={{ fontFamily: UI, fontSize: 14, color: c.t3, marginTop: 4 }}>{l.goRide}</div>
        </div>
      )}
      <Filters show={showF} onClose={() => setShowF(false)} filters={f} setF={setF} c={c} l={l} />
    </div>
  );
};

// ═══════════════════════════════════════
// RECORD
// ═══════════════════════════════════════

const RecordScreen = ({ c, l, isRecording, isPaused, elapsed, recDist, onStart, onPause, onResume, onStop }) => {
  const [locationMode, setLocationMode] = useState(0); // 0: arrow, 1: filled, 2: compass
  const fmt = s => { const h = Math.floor(s / 3600); const m = Math.floor((s % 3600) / 60); const sec = s % 60; return `${h > 0 ? h + ":" : ""}${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`; };
  const spd = isRecording && !isPaused ? Math.floor(Math.random() * 30 + 50) : 0;
  const LocationIcon = locationMode === 0 ? I.locationArrow : locationMode === 1 ? I.locationArrowFilled : I.compass;
  const cycleLocation = () => setLocationMode(m => (m + 1) % 3);

  return (
    <div style={{ padding: "0 16px 100px", display: "flex", flexDirection: "column", minHeight: "calc(100vh - 100px)" }}>
      <div style={{ padding: "56px 0 12px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span style={{ fontFamily: UI, fontSize: 20, fontWeight: 800, color: c.text }}>{l.record}</span>
        {isRecording && <Badge color={isPaused ? "#FFB347" : c.accent}>{isPaused ? "PAUSED" : "● REC"}</Badge>}
      </div>

      {/* Map */}
      <div style={{ flex: 1, minHeight: 260, borderRadius: 16, overflow: "hidden", position: "relative", background: c.mapBg, marginBottom: 12 }}>
        <div style={{ position: "absolute", inset: 0, opacity: 0.08, backgroundImage: `linear-gradient(${c.t3} 1px, transparent 1px), linear-gradient(90deg, ${c.t3} 1px, transparent 1px)`, backgroundSize: "24px 24px" }} />

        {isRecording && (
          <svg width="100%" height="100%" style={{ position: "absolute", inset: 0 }}>
            <path d={`M 40 200 Q 80 160 130 150 T 220 110 T 310 80 T ${310 + recDist * 5} ${80 - recDist * 2}`}
              stroke={c.accent} strokeWidth="3.5" fill="none" strokeLinecap="round" style={{ filter: `drop-shadow(0 0 4px ${c.accent}40)` }} />
            <circle cx={310 + recDist * 5} cy={80 - recDist * 2} r="6" fill={c.accent} />
            <circle cx="40" cy="200" r="5" fill={c.green} />
          </svg>
        )}

        {/* User location dot + cone (always visible on map) */}
        <div style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%, -50%)", width: 48, height: 48 }}>
          <div style={{ position: "absolute", left: "50%", top: "50%", width: 20, height: 20, borderRadius: 10, background: c.accent, transform: "translate(-50%, -50%)", animation: "pulse 2s ease-in-out infinite", opacity: 0.9 }} />
          <svg width={48} height={48} viewBox="0 0 48 48" style={{ position: "absolute", left: 0, top: 0, animation: "rotateCone 8s linear infinite" }}>
            <path d="M24 4 L44 24 L24 20 Z" fill={c.accent} opacity={0.6} />
          </svg>
        </div>

        {/* Car pill */}
        <div style={{ position: "absolute", top: 12, left: 12, background: c.card, borderRadius: 12, padding: "8px 12px", display: "flex", alignItems: "center", gap: 8, boxShadow: "0 2px 8px rgba(0,0,0,0.15)" }}>
          {I.car(c.accent, 16)}
          <span style={{ fontFamily: UI, fontSize: 13, fontWeight: 700, color: c.text }}>VW Polo 2018</span>
        </div>

        {/* Map controls: zoom -, zoom +, location */}
        <div style={{ position: "absolute", right: 12, bottom: 16, display: "flex", flexDirection: "column", gap: 8, alignItems: "center" }}>
          <button style={{ width: 44, height: 44, borderRadius: 22, background: c.glass, backdropFilter: c.glassBlur, border: `1px solid ${c.glassBorder}`, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>{I.minus(c.text, 20)}</button>
          <button style={{ width: 44, height: 44, borderRadius: 22, background: c.glass, backdropFilter: c.glassBlur, border: `1px solid ${c.glassBorder}`, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>{I.plus(c.text, 20)}</button>
          <button onClick={cycleLocation} style={{ width: 44, height: 44, borderRadius: 22, background: c.glass, backdropFilter: c.glassBlur, border: `1px solid ${c.glassBorder}`, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>{LocationIcon(c.text, 20)}</button>
        </div>

        {/* Speed */}
        {isRecording && (
          <div style={{ position: "absolute", bottom: 16, left: "50%", transform: "translateX(-50%)", textAlign: "center", background: c.card, borderRadius: 16, padding: "12px 24px", boxShadow: "0 4px 16px rgba(0,0,0,0.15)" }}>
            <div style={{ fontFamily: UI, fontSize: 44, fontWeight: 900, color: c.text, lineHeight: 1, letterSpacing: -2 }}>{spd}</div>
            <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, fontWeight: 600, letterSpacing: 1 }}>КМ/Ч</div>
          </div>
        )}
      </div>

      {/* Live stats */}
      {isRecording && (
        <Card c={c} style={{ marginBottom: 12 }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", textAlign: "center" }}>
            {[
              { val: fmt(elapsed), label: "Время", color: c.text },
              { val: recDist.toFixed(1), label: "Км", color: c.accent },
              { val: elapsed > 0 ? ((recDist / elapsed) * 3600).toFixed(0) : "0", label: "Ср. км/ч", color: c.text },
            ].map((s, i) => (
              <div key={i}>
                <div style={{ fontFamily: UI, fontSize: 22, fontWeight: 800, color: s.color }}>{s.val}</div>
                <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, marginTop: 2 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Controls */}
      <div style={{ display: "flex", justifyContent: "center", gap: 16, padding: "8px 0" }}>
        {!isRecording ? (
          <button onClick={onStart} style={{ width: 72, height: 72, borderRadius: 36, background: c.accent, border: "none", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", boxShadow: `0 4px 20px ${c.accent}40` }}>
            {I.play("#fff", 28)}
          </button>
        ) : (
          <>
            <button onClick={isPaused ? onResume : onPause} style={{ width: 56, height: 56, borderRadius: 28, background: c.card, border: "none", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
              {isPaused ? I.play(c.text, 22) : I.pause(c.text, 22)}
            </button>
            <button onClick={onStop} style={{ width: 56, height: 56, borderRadius: 28, background: c.red, border: "none", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", boxShadow: `0 4px 16px ${c.red}30` }}>
              {I.stop("#fff", 20)}
            </button>
          </>
        )}
      </div>
      {!isRecording && <div style={{ textAlign: "center", marginTop: 8, fontFamily: UI, fontSize: 13, color: c.t3 }}>{l.start}</div>}
    </div>
  );
};

// ═══════════════════════════════════════
// REGIONS — Fog of War map + list
// ═══════════════════════════════════════

// Mock corridor paths (percent of 100x100 viewBox) for SVG mask — "burned" routes
const FOG_CORRIDORS = [
  "M 20 50 Q 35 35 50 45 T 80 40 T 95 55",
  "M 30 70 Q 45 55 60 65 L 75 60 L 85 75",
  "M 15 30 L 40 25 L 55 50 L 70 45",
  "M 60 20 L 75 35 Q 85 50 80 70",
];

const FogOfWarMap = ({ c, onTapCleared }) => {
  const w = 100;
  const h = 100;
  const strokeWidth = 14;
  return (
    <div
      onClick={onTapCleared}
      style={{ position: "relative", width: "100%", paddingBottom: "72%", background: c.mapBg, cursor: "pointer", overflow: "hidden" }}
    >
      {/* Grid */}
      <div style={{ position: "absolute", inset: 0, opacity: 0.08, backgroundImage: `linear-gradient(${c.t3} 1px, transparent 1px), linear-gradient(90deg, ${c.t3} 1px, transparent 1px)`, backgroundSize: "12% 12%" }} />
      {/* Fog: full rect masked by (white - blurred black corridors) so corridors show map */}
      <svg width="100%" height="100%" style={{ position: "absolute", inset: 0 }} viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none">
        <defs>
          <filter id="fogBlur" x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur in="SourceGraphic" stdDeviation="2.5" result="blur" />
          </filter>
          <mask id="fogMask">
            <rect x="0" y="0" width={w} height={h} fill="white" />
            <g filter="url(#fogBlur)">
              {FOG_CORRIDORS.map((d, i) => (
                <path key={i} d={d} fill="none" stroke="black" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
              ))}
            </g>
          </mask>
        </defs>
        <rect x="0" y="0" width={w} height={h} fill={c.fog} mask="url(#fogMask)" />
      </svg>
    </div>
  );
};

const RegionsScreen = ({ c, l, onSelect }) => {
  const [sel, setSel] = useState(null);
  const unlocked = REGIONS.filter(r => r.unlocked).length;

  return (
    <div style={{ padding: "0 16px 100px" }}>
      <div style={{ padding: "56px 0 12px" }}>
        <span style={{ fontFamily: UI, fontSize: 20, fontWeight: 800, color: c.text }}>{l.regions}</span>
      </div>

      {/* Progress */}
      <Card c={c} style={{ marginBottom: 10 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
          <Badge>LVL {unlocked}</Badge>
          <span style={{ fontFamily: UI, fontSize: 13, color: c.t2, fontWeight: 600 }}>{unlocked} из {REGIONS.length} {l.unlocked}</span>
        </div>
        <div style={{ height: 6, borderRadius: 3, background: c.cardAlt, overflow: "hidden" }}>
          <div style={{ height: "100%", borderRadius: 3, width: `${(unlocked / REGIONS.length) * 100}%`, background: c.accent, transition: "width .5s" }} />
        </div>
      </Card>

      {/* Fog of War Map */}
      <Card c={c} style={{ padding: 0, overflow: "hidden", marginBottom: 10 }}>
        <FogOfWarMap c={c} onTapCleared={() => { const first = REGIONS.find(r => r.unlocked); if (first) setSel(first.id); }} />
      </Card>

      {/* Selected */}
      {sel && (() => {
        const r = REGIONS.find(x => x.id === sel);
        const totalKmInRegion = TRIPS.filter(t => t.region === r.name).reduce((s, t) => s + t.distance, 0);
        return (
          <Card c={c} style={{ marginBottom: 10, animation: "fadeUp .25s ease" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div>
                <Badge>UNLOCKED</Badge>
                <div style={{ fontFamily: UI, fontSize: 18, fontWeight: 800, color: c.text, margin: "6px 0 2px" }}>{r.name}</div>
                <div style={{ fontFamily: UI, fontSize: 13, color: c.t2 }}>{l.km}: {totalKmInRegion.toFixed(0)} · {r.trips} {l.trips}</div>
              </div>
              <button onClick={() => { onSelect(r.name); setSel(null); }} style={{ background: c.accent, border: "none", borderRadius: 14, padding: "12px 20px", color: "#fff", fontSize: 14, fontWeight: 700, fontFamily: UI, cursor: "pointer" }}>
                {l.view} →
              </button>
            </div>
          </Card>
        );
      })()}

      {/* List */}
      <Card c={c} style={{ padding: 0 }}>
        {REGIONS.map((r, i) => (
          <div key={r.id} onClick={() => r.unlocked && setSel(r.id)} style={{
            display: "flex", alignItems: "center", gap: 12, padding: "14px 16px",
            borderBottom: i < REGIONS.length - 1 ? `1px solid ${c.border}` : "none",
            cursor: r.unlocked ? "pointer" : "default", opacity: r.unlocked ? 1 : 0.35,
          }}>
            <div style={{ width: 36, height: 36, borderRadius: 10, background: r.unlocked ? c.accentBg : c.cardAlt, display: "flex", alignItems: "center", justifyContent: "center" }}>
              {r.unlocked ? I.check(c.accent, 18) : I.lock(c.t3, 16)}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: UI, fontSize: 15, fontWeight: 700, color: c.text }}>{r.name}</div>
              <div style={{ fontFamily: UI, fontSize: 12, color: c.t3 }}>{r.unlocked ? `${r.trips} ${l.trips}` : l.locked}</div>
            </div>
            {r.unlocked && <span style={{ fontFamily: UI, fontSize: 16, color: c.t3 }}>›</span>}
          </div>
        ))}
      </Card>
    </div>
  );
};

// ═══════════════════════════════════════
// PROFILE
// ═══════════════════════════════════════

const ProfileScreen = ({ c, l, themeMode, setTheme, lang, setLang, onBack }) => {
  const [avatar, setAvatar] = useState("🏎️");
  const [car, setCar] = useState("VW Polo 2018");
  return (
    <div style={{ padding: "0 16px 40px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "56px 0 16px" }}>
        <button onClick={onBack} style={{ background: c.card, border: "none", borderRadius: 12, padding: "8px 14px", fontFamily: UI, fontSize: 14, fontWeight: 600, color: c.text, cursor: "pointer", display: "flex", alignItems: "center", gap: 6 }}>
          {I.back(c.t2, 16)} {l.back}
        </button>
      </div>
      {/* Avatar */}
      <Card c={c} style={{ textAlign: "center", marginBottom: 10, padding: 20 }}>
        <div style={{ width: 72, height: 72, borderRadius: 36, margin: "0 auto 14px", background: c.cardAlt, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 34 }}>{avatar}</div>
        <div style={{ display: "flex", gap: 8, justifyContent: "center", flexWrap: "wrap" }}>
          {AVATARS.map(a => (
            <button key={a} onClick={() => setAvatar(a)} style={{ width: 42, height: 42, borderRadius: 12, background: avatar === a ? c.accentBg : c.cardAlt, border: avatar === a ? `2px solid ${c.accent}` : "2px solid transparent", fontSize: 20, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>{a}</button>
          ))}
        </div>
      </Card>
      {/* Car */}
      <Card c={c} style={{ marginBottom: 10 }}>
        <div style={{ fontFamily: UI, fontSize: 13, color: c.t2, fontWeight: 600, marginBottom: 8, display: "flex", alignItems: "center", gap: 6 }}>{I.car(c.accent, 16)} {l.garage}</div>
        <input value={car} onChange={e => setCar(e.target.value)} style={{ width: "100%", background: c.cardAlt, border: "none", borderRadius: 12, padding: "12px 14px", color: c.text, fontSize: 16, fontFamily: UI, fontWeight: 700, outline: "none", boxSizing: "border-box" }} />
      </Card>
      {/* Theme */}
      <Card c={c} style={{ marginBottom: 10 }}>
        <div style={{ fontFamily: UI, fontSize: 13, color: c.t2, fontWeight: 600, marginBottom: 10, display: "flex", alignItems: "center", gap: 6 }}>{I.sun(c.accent, 16)} {l.theme}</div>
        <div style={{ display: "flex", gap: 8 }}>
          {[{ k: "dark", lb: l.dark, icon: I.moon }, { k: "light", lb: l.light, icon: I.sun }].map(o => (
            <Chip key={o.k} c={c} active={themeMode === o.k} onClick={() => setTheme(o.k)} style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", gap: 6 }}>
              {o.icon(themeMode === o.k ? "#fff" : c.t2, 14)} {o.lb}
            </Chip>
          ))}
        </div>
      </Card>
      {/* Language */}
      <Card c={c} style={{ marginBottom: 10 }}>
        <div style={{ fontFamily: UI, fontSize: 13, color: c.t2, fontWeight: 600, marginBottom: 10, display: "flex", alignItems: "center", gap: 6 }}>{I.globe(c.accent, 16)} {l.lang}</div>
        <div style={{ display: "flex", gap: 8 }}>
          {[{ k: "ru", lb: "Русский" }, { k: "en", lb: "English" }].map(o => (
            <Chip key={o.k} c={c} active={lang === o.k} onClick={() => setLang(o.k)} style={{ flex: 1, textAlign: "center" }}>{o.lb}</Chip>
          ))}
        </div>
      </Card>
      {/* About */}
      <Card c={c} style={{ textAlign: "center" }}>
        <span style={{ fontFamily: PX, fontSize: 9, color: c.accent, letterSpacing: 1 }}>ROAD TRIP TRACKER</span>
        <div style={{ fontFamily: UI, fontSize: 13, color: c.t2, marginTop: 6 }}>v0.1.0 MVP</div>
        <div style={{ fontFamily: UI, fontSize: 12, color: c.t3, marginTop: 2 }}>{l.author}: OneZee</div>
      </Card>
    </div>
  );
};

// ═══════════════════════════════════════
// STATS
// ═══════════════════════════════════════

const StatsScreen = ({ c, l, onBack }) => {
  const [period, setPeriod] = useState("total");
  const [fuelPrice, setFuelPrice] = useState(56);
  const [cons, setCons] = useState(7.8);
  const totD = TRIPS.reduce((s, t) => s + t.distance, 0);
  const totF = TRIPS.reduce((s, t) => s + t.fuel, 0);
  const totM = TRIPS.reduce((s, t) => s + t.durationMin, 0);
  const avgS = totD / (totM / 60);
  const tripDates = TRIPS.reduce((a, t) => { a[t.dateFull] = (a[t.dateFull] || 0) + t.distance; return a; }, {});
  const calDays = [];
  const fow = new Date(2026, 1, 1).getDay() || 7;
  for (let i = 1; i < fow; i++) calDays.push(null);
  for (let d = 1; d <= 28; d++) calDays.push({ day: d, km: tripDates[`2026-02-${String(d).padStart(2, "0")}`] || 0 });
  const inp = { width: "100%", background: c.cardAlt, border: "none", borderRadius: 12, padding: "12px 14px", color: c.text, fontSize: 15, fontFamily: UI, outline: "none", boxSizing: "border-box" };

  return (
    <div style={{ padding: "0 16px 40px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "56px 0 16px" }}>
        <button onClick={onBack} style={{ background: c.card, border: "none", borderRadius: 12, padding: "8px 14px", fontFamily: UI, fontSize: 14, fontWeight: 600, color: c.text, cursor: "pointer", display: "flex", alignItems: "center", gap: 6 }}>
          {I.back(c.t2, 16)} {l.back}
        </button>
      </div>

      <div style={{ display: "flex", gap: 6, marginBottom: 12 }}>
        {[{ k: "week", lb: l.week }, { k: "month", lb: l.month }, { k: "year", lb: l.year }, { k: "total", lb: l.total }].map(p => (
          <Chip key={p.k} c={c} active={period === p.k} onClick={() => setPeriod(p.k)} style={{ flex: 1, textAlign: "center" }}>{p.lb}</Chip>
        ))}
      </div>

      {/* Main stats */}
      <Card c={c} style={{ marginBottom: 10 }}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px 24px" }}>
          {[
            { val: `${totD.toFixed(0)} км`, label: "Дистанция", icon: I.route(c.accent, 20) },
            { val: TRIPS.length, label: "Поездок", icon: I.flag(c.accent, 20) },
            { val: `${Math.floor(totM / 60)}ч ${totM % 60}м`, label: "В пути", icon: I.clock(c.accent, 20) },
            { val: `${avgS.toFixed(0)} км/ч`, label: "Ср. скорость", icon: I.speed(c.accent, 20) },
            { val: `${totF.toFixed(1)} л`, label: "Топлива", icon: I.fuel(c.accent, 20) },
            { val: `${(totF * fuelPrice).toFixed(0)} ₽`, label: "На бензин", icon: I.fuel(c.accent, 20) },
          ].map((s, i) => (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 40, height: 40, borderRadius: 12, background: c.accentBg, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                {s.icon}
              </div>
              <div>
                <div style={{ fontFamily: UI, fontSize: 18, fontWeight: 800, color: c.text }}>{s.val}</div>
                <div style={{ fontFamily: UI, fontSize: 11, color: c.t3 }}>{s.label}</div>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* Calendar Heatmap — always expanded, view-only, relative intensity */}
      <Card c={c} style={{ marginBottom: 10 }}>
        <div style={{ fontFamily: UI, fontSize: 15, fontWeight: 700, color: c.text, marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
          {I.calendar(c.accent, 18)} {l.calendar} — Февраль 2026
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4, marginBottom: 4 }}>
          {["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"].map(d => (
            <div key={d} style={{ textAlign: "center", fontFamily: UI, fontSize: 10, color: c.t3, fontWeight: 600 }}>{d}</div>
          ))}
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4 }}>
          {calDays.map((cell, i) => {
            const km = cell ? cell.km : 0;
            const maxK = Math.max(1, ...Object.values(tripDates));
            const r = maxK > 0 ? km / maxK : 0;
            const op = r <= 1/3 ? 0.15 : r <= 2/3 ? 0.4 : 0.9;
            return (
              <div key={i} style={{
                aspectRatio: "1", borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", flexDirection: "column",
                background: cell ? (km > 0 ? c.accent : c.cardAlt) : "transparent", opacity: cell && km > 0 ? op : 1,
                border: "none", pointerEvents: "none",
              }}>
                {cell && (
                  <>
                    <span style={{ fontFamily: UI, fontSize: 12, color: cell.km > 0 ? "#fff" : c.t3, fontWeight: cell.km > 0 ? 700 : 400 }}>{cell.day}</span>
                    {cell.km > 0 && <span style={{ fontFamily: UI, fontSize: 7, color: "rgba(255,255,255,0.9)", fontWeight: 700 }}>{cell.km.toFixed(0)}</span>}
                  </>
                )}
              </div>
            );
          })}
        </div>
      </Card>

      {/* Fuel calculator */}
      <Card c={c}>
        <div style={{ fontFamily: UI, fontSize: 15, fontWeight: 700, color: c.text, marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
          {I.fuel(c.accent, 18)} Расход топлива
        </div>
        <div style={{ display: "flex", gap: 10, marginBottom: 14 }}>
          {[{ lbl: l.consumption, val: cons, set: setCons, step: "0.1" }, { lbl: l.priceL, val: fuelPrice, set: setFuelPrice, step: "1" }].map((f, i) => (
            <div key={i} style={{ flex: 1 }}>
              <div style={{ fontFamily: UI, fontSize: 12, color: c.t3, fontWeight: 600, marginBottom: 6 }}>{f.lbl}</div>
              <input type="number" step={f.step} value={f.val} onChange={e => f.set(+e.target.value)} style={inp} />
            </div>
          ))}
        </div>
        <div style={{ background: c.cardAlt, borderRadius: 12, padding: 14, display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, textAlign: "center" }}>
          {[
            { val: totD.toFixed(0), label: "км" },
            { val: ((totD / 100) * cons).toFixed(1), label: "литров" },
            { val: `${((totD / 100) * cons * fuelPrice).toFixed(0)} ₽`, label: "итого" },
          ].map((x, i) => (
            <div key={i}>
              <div style={{ fontFamily: UI, fontSize: 20, fontWeight: 800, color: c.accent }}>{x.val}</div>
              <div style={{ fontFamily: UI, fontSize: 11, color: c.t3, marginTop: 2 }}>{x.label}</div>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};

// ═══════════════════════════════════════
// RECORDING HUD — compact pill on Feed/Regions when recording
// ═══════════════════════════════════════

const RecordingHUD = ({ tab, onGoToRecord, isRecording, isPaused, elapsed, recDist, c, l }) => {
  if (tab === "record" || !isRecording) return null;
  const fmt = s => { const h = Math.floor(s / 3600); const m = Math.floor((s % 3600) / 60); const sec = s % 60; return `${h > 0 ? h + ":" : ""}${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`; };
  return (
    <button
      onClick={onGoToRecord}
      style={{
        position: "fixed", top: 64, right: 16, zIndex: 60,
        display: "flex", alignItems: "center", gap: 8,
        background: c.glass, backdropFilter: c.glassBlur, WebkitBackdropFilter: c.glassBlur,
        border: `1px solid ${c.glassBorder}`, borderRadius: 20, padding: "8px 14px",
        boxShadow: c.glassShadow, cursor: "pointer",
        fontFamily: UI, fontSize: 12, fontWeight: 600, color: c.text,
      }}
    >
      <span style={{ width: 6, height: 6, borderRadius: 3, background: isPaused ? "#FFB347" : c.accent, animation: isPaused ? "none" : "pulse 1.5s ease-in-out infinite" }} />
      <span style={{ fontFamily: PX, fontSize: 6, color: isPaused ? "#FFB347" : c.accent }}>{isPaused ? "PAUSED" : "REC"}</span>
      <span style={{ color: c.t2 }}>{recDist.toFixed(1)} {l.km}</span>
      <span style={{ color: c.t3 }}>·</span>
      <span style={{ color: c.t2 }}>{fmt(elapsed)}</span>
    </button>
  );
};

// ═══════════════════════════════════════
// TAB BAR — iOS 26 Liquid Glass floating
// ═══════════════════════════════════════

const TabBar = ({ tab, setTab, c, l }) => (
  <div style={{
    position: "fixed", bottom: 16, left: "50%", transform: "translateX(-50%)",
    width: "calc(100% - 48px)", maxWidth: 360,
    background: c.glass,
    backdropFilter: c.glassBlur, WebkitBackdropFilter: c.glassBlur,
    border: `1px solid ${c.glassBorder}`,
    borderRadius: 28, boxShadow: c.glassShadow,
    display: "flex", justifyContent: "space-around", alignItems: "center",
    padding: "6px 4px", zIndex: 50, overflow: "hidden",
  }}>
    {/* Glass shine overlay */}
    <div style={{ position: "absolute", inset: 0, borderRadius: 28, background: c.glassShine, pointerEvents: "none" }} />

    {[
      { key: "feed", icon: I.flag, label: l.feed },
      { key: "record", icon: I.car, label: l.record, center: true },
      { key: "regions", icon: I.map, label: l.regions },
    ].map(t => (
      <button key={t.key} onClick={() => setTab(t.key)} style={{
        position: "relative", zIndex: 1,
        display: "flex", flexDirection: "column", alignItems: "center", gap: 2,
        background: "none", border: "none", cursor: "pointer", padding: "4px 18px",
      }}>
        {t.center ? (
          <div style={{
            width: 48, height: 48, borderRadius: 24,
            background: c.accent, display: "flex", alignItems: "center", justifyContent: "center",
            marginTop: -6, boxShadow: `0 4px 16px ${c.accent}40`,
            transition: "transform .2s", transform: tab === "record" ? "scale(1.05)" : "scale(1)",
          }}>
            {t.icon("#fff", 22)}
          </div>
        ) : t.icon(tab === t.key ? c.accent : c.t3, 22)}
        <span style={{
          fontFamily: UI, fontSize: 10, fontWeight: 600,
          color: tab === t.key ? c.accent : c.t3,
        }}>{t.label}</span>
      </button>
    ))}
  </div>
);

// ═══════════════════════════════════════
// APP
// ═══════════════════════════════════════

export default function App() {
  const [tab, setTab] = useState("feed");
  const [overlay, setOverlay] = useState(null);
  const [themeMode, setTheme] = useState("dark");
  const [lang, setLang] = useState("ru");
  const [regF, setRegF] = useState(null);
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [recDist, setRecDist] = useState(0);
  const c = themeMode === "light" ? C.light : C.dark;
  const l = L[lang];

  const recordingIntervalRef = useRef(null);
  useEffect(() => {
    if (isRecording && !isPaused) {
      recordingIntervalRef.current = setInterval(() => {
        setElapsed(e => e + 1);
        setRecDist(d => d + Math.random() * 0.02 + 0.005);
      }, 1000);
    } else {
      if (recordingIntervalRef.current) clearInterval(recordingIntervalRef.current);
    }
    return () => { if (recordingIntervalRef.current) clearInterval(recordingIntervalRef.current); };
  }, [isRecording, isPaused]);

  const onStart = () => { setIsRecording(true); setIsPaused(false); };
  const onPause = () => setIsPaused(true);
  const onResume = () => setIsPaused(false);
  const onStop = () => { setIsRecording(false); setIsPaused(false); setElapsed(0); setRecDist(0); };

  return (
    <div style={{ background: c.bg, minHeight: "100vh", maxWidth: 420, margin: "0 auto", position: "relative", fontFamily: UI, transition: "background .3s ease", WebkitFontSmoothing: "antialiased" }}>
      <link href="https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700;9..40,800;9..40,900&family=Press+Start+2P&display=swap" rel="stylesheet" />
      <style>{`
        @keyframes fadeUp { from { opacity:0; transform:translateY(10px) } to { opacity:1; transform:translateY(0) } }
        @keyframes fadeIn { from { opacity:0 } to { opacity:1 } }
        @keyframes slideUp { from { transform:translateY(100%) } to { transform:translateY(0) } }
        @keyframes pulse { 0%,100% { transform:scale(1); opacity:1 } 50% { transform:scale(1.15); opacity:0.7 } }
        @keyframes rotateCone { from { transform:rotate(0deg) } to { transform:rotate(360deg) } }
        input[type=number]::-webkit-inner-spin-button, input[type=number]::-webkit-outer-spin-button { -webkit-appearance:none }
        * { box-sizing:border-box } ::-webkit-scrollbar { width:0 }
      `}</style>

      <div style={{ position: "relative", zIndex: 1 }}>
        {overlay === "profile" ? <ProfileScreen c={c} l={l} themeMode={themeMode} setTheme={setTheme} lang={lang} setLang={setLang} onBack={() => setOverlay(null)} />
          : overlay === "stats" ? <StatsScreen c={c} l={l} onBack={() => setOverlay(null)} />
          : tab === "feed" ? <FeedScreen c={c} l={l} lang={lang} onProfile={() => setOverlay("profile")} onStats={() => setOverlay("stats")} regF={regF} clearRegF={() => setRegF(null)} />
          : tab === "record" ? <RecordScreen c={c} l={l} isRecording={isRecording} isPaused={isPaused} elapsed={elapsed} recDist={recDist} onStart={onStart} onPause={onPause} onResume={onResume} onStop={onStop} />
          : <RegionsScreen c={c} l={l} onSelect={name => { setRegF(name); setTab("feed"); }} />}
      </div>

      {!overlay && <RecordingHUD tab={tab} onGoToRecord={() => setTab("record")} isRecording={isRecording} isPaused={isPaused} elapsed={elapsed} recDist={recDist} c={c} l={l} />}
      {!overlay && <TabBar tab={tab} setTab={setTab} c={c} l={l} />}
    </div>
  );
}
