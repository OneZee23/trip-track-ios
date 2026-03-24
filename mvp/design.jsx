import { useState, useEffect, useRef, useCallback } from "react";

// ─── Mock Data ───────────────────────────────────────────────────────────
const MOCK_TRIPS = [
  { id: 1, date: "28 янв 2026", time: "14:30", distance: 145.3, duration: "2ч 15м", avgSpeed: 64, maxSpeed: 132, regions: ["Краснодарский край", "Адыгея"], route: [[45.04, 38.97], [45.1, 39.1], [45.2, 39.3], [44.95, 39.7], [44.6, 40.1]] },
  { id: 2, date: "15 янв 2026", time: "09:00", distance: 87.6, duration: "1ч 32м", avgSpeed: 57, maxSpeed: 118, regions: ["Краснодарский край"], route: [[45.04, 38.97], [45.1, 38.8], [45.2, 38.6], [45.35, 38.5]] },
  { id: 3, date: "3 янв 2026", time: "11:15", distance: 234.1, duration: "3ч 48м", avgSpeed: 62, maxSpeed: 145, regions: ["Краснодарский край", "Ростовская область"], route: [[45.04, 38.97], [45.3, 39.5], [46.0, 39.8], [46.7, 39.7], [47.2, 39.7]] },
  { id: 4, date: "28 дек 2025", time: "07:45", distance: 312.7, duration: "4ч 22м", avgSpeed: 72, maxSpeed: 156, regions: ["Краснодарский край", "Ставропольский край"], route: [[45.04, 38.97], [44.8, 39.5], [44.5, 40.2], [44.2, 41.0], [44.0, 41.9]] },
  { id: 5, date: "20 дек 2025", time: "16:00", distance: 52.4, duration: "0ч 58м", avgSpeed: 54, maxSpeed: 95, regions: ["Краснодарский край"], route: [[45.04, 38.97], [45.1, 39.05], [45.15, 39.15]] },
];

const REGIONS_DATA = [
  { name: "Краснодарский край", trips: 12, km: 1845, firstVisit: "2024-03-15", intensity: 1.0 },
  { name: "Адыгея", trips: 3, km: 320, firstVisit: "2024-06-20", intensity: 0.4 },
  { name: "Ростовская область", trips: 5, km: 890, firstVisit: "2024-05-01", intensity: 0.65 },
  { name: "Ставропольский край", trips: 2, km: 410, firstVisit: "2025-01-10", intensity: 0.3 },
  { name: "Волгоградская область", trips: 1, km: 180, firstVisit: "2025-04-12", intensity: 0.15 },
  { name: "Крым", trips: 4, km: 1200, firstVisit: "2024-07-01", intensity: 0.8 },
  { name: "Карачаево-Черкесия", trips: 2, km: 290, firstVisit: "2025-02-14", intensity: 0.25 },
  { name: "Кабардино-Балкария", trips: 1, km: 155, firstVisit: "2025-08-20", intensity: 0.12 },
];

const ACHIEVEMENTS = [
  { id: 1, icon: "🎯", title: "Первая поездка", desc: "Завершил первую поездку", unlocked: true, progress: 1, total: 1 },
  { id: 2, icon: "🛣️", title: "Сотня", desc: "Проехал 100 км", unlocked: true, progress: 100, total: 100 },
  { id: 3, icon: "🚀", title: "Пятьсот", desc: "Проехал 500 км", unlocked: true, progress: 500, total: 500 },
  { id: 4, icon: "🏔️", title: "Тысяча", desc: "Проехал 1000 км", unlocked: true, progress: 1000, total: 1000 },
  { id: 5, icon: "🌍", title: "Исследователь", desc: "Посетил 5 регионов", unlocked: true, progress: 5, total: 5 },
  { id: 6, icon: "🏆", title: "Путешественник", desc: "Посетил 10 регионов", unlocked: false, progress: 8, total: 10 },
  { id: 7, icon: "⭐", title: "Марафонец", desc: "Проехал 5000 км", unlocked: false, progress: 3890, total: 5000 },
  { id: 8, icon: "👑", title: "Легенда дорог", desc: "Посетил 25 регионов", unlocked: false, progress: 8, total: 25 },
];

// ─── Styles ──────────────────────────────────────────────────────────────
const styles = `
  @import url('https://fonts.googleapis.com/css2?family=SF+Pro+Display:wght@300;400;500;600;700;800;900&display=swap');

  :root {
    --glass-bg: rgba(28, 28, 30, 0.72);
    --glass-bg-light: rgba(28, 28, 30, 0.55);
    --glass-border: rgba(255, 255, 255, 0.08);
    --glass-border-bright: rgba(255, 255, 255, 0.15);
    --glass-highlight: rgba(255, 255, 255, 0.04);
    --text-primary: rgba(255, 255, 255, 0.95);
    --text-secondary: rgba(255, 255, 255, 0.55);
    --text-tertiary: rgba(255, 255, 255, 0.35);
    --blue: #0A84FF;
    --blue-dim: rgba(10, 132, 255, 0.25);
    --green: #30D158;
    --green-dim: rgba(48, 209, 88, 0.2);
    --orange: #FF9F0A;
    --orange-dim: rgba(255, 159, 10, 0.2);
    --red: #FF453A;
    --red-dim: rgba(255, 69, 58, 0.2);
    --purple: #BF5AF2;
    --purple-dim: rgba(191, 90, 242, 0.2);
    --teal: #64D2FF;
    --surface: #1C1C1E;
    --surface-elevated: #2C2C2E;
    --safe-bottom: 34px;
    --safe-top: 59px;
  }

  * { margin: 0; padding: 0; box-sizing: border-box; -webkit-font-smoothing: antialiased; }

  body { background: #000; }

  .phone-frame {
    width: 393px; height: 852px;
    background: #000;
    border-radius: 47px;
    overflow: hidden;
    position: relative;
    border: 1px solid rgba(255,255,255,0.1);
    box-shadow: 0 0 0 4px #1a1a1a, 0 40px 80px rgba(0,0,0,0.8);
    font-family: -apple-system, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif;
    color: var(--text-primary);
  }

  /* Dynamic Island */
  .dynamic-island {
    position: absolute; top: 11px; left: 50%; transform: translateX(-50%);
    width: 126px; height: 37px; background: #000; border-radius: 20px; z-index: 100;
  }

  /* Status Bar */
  .status-bar {
    position: absolute; top: 0; left: 0; right: 0; height: var(--safe-top);
    display: flex; justify-content: space-between; align-items: flex-end;
    padding: 0 32px 8px; z-index: 90; font-size: 15px; font-weight: 600;
    color: var(--text-primary);
  }
  .status-bar-icons { display: flex; gap: 5px; align-items: center; }

  /* ─── Liquid Glass Material ─── */
  .glass {
    background: var(--glass-bg);
    backdrop-filter: blur(40px) saturate(180%);
    -webkit-backdrop-filter: blur(40px) saturate(180%);
    border: 1px solid var(--glass-border);
  }

  .glass-light {
    background: var(--glass-bg-light);
    backdrop-filter: blur(60px) saturate(200%);
    -webkit-backdrop-filter: blur(60px) saturate(200%);
    border: 1px solid var(--glass-border-bright);
  }

  .glass-pill {
    background: rgba(255,255,255,0.08);
    backdrop-filter: blur(20px);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 100px;
    padding: 6px 14px;
    font-size: 13px;
    font-weight: 500;
    color: var(--text-secondary);
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .glass-pill:hover, .glass-pill.active {
    background: rgba(255,255,255,0.15);
    color: var(--text-primary);
    border-color: rgba(255,255,255,0.12);
  }

  /* ─── Map Background ─── */
  .map-bg {
    position: absolute; inset: 0;
    background:
      radial-gradient(circle at 60% 40%, rgba(10, 132, 255, 0.08) 0%, transparent 50%),
      radial-gradient(circle at 30% 70%, rgba(48, 209, 88, 0.05) 0%, transparent 40%),
      linear-gradient(180deg, #0d1117 0%, #161b22 40%, #1a1f26 100%);
  }

  .map-grid {
    position: absolute; inset: 0; opacity: 0.04;
    background-image:
      linear-gradient(rgba(255,255,255,0.5) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,0.5) 1px, transparent 1px);
    background-size: 60px 60px;
  }

  .map-road {
    position: absolute;
    stroke: var(--blue);
    stroke-width: 3;
    fill: none;
    filter: drop-shadow(0 0 6px rgba(10, 132, 255, 0.4));
  }

  .map-road-glow {
    stroke: rgba(10, 132, 255, 0.15);
    stroke-width: 16;
    fill: none;
  }

  /* Current position dot */
  .current-pos {
    position: absolute;
    width: 16px; height: 16px;
    background: var(--blue);
    border-radius: 50%;
    border: 3px solid #fff;
    box-shadow: 0 0 20px rgba(10, 132, 255, 0.6), 0 0 40px rgba(10, 132, 255, 0.3);
    z-index: 10;
  }

  .current-pos::after {
    content: '';
    position: absolute; top: -8px; left: -8px; right: -8px; bottom: -8px;
    border-radius: 50%;
    background: rgba(10, 132, 255, 0.15);
    animation: pulse-ring 2s ease-out infinite;
  }

  @keyframes pulse-ring {
    0% { transform: scale(1); opacity: 0.6; }
    100% { transform: scale(2.5); opacity: 0; }
  }

  /* ─── HUD Panel (idle state) ─── */
  .hud-panel {
    position: absolute; bottom: 0; left: 0; right: 0;
    padding: 0 16px calc(var(--safe-bottom) + 70px) 16px;
    z-index: 20;
  }

  .hud-card {
    border-radius: 28px;
    padding: 28px 24px 24px;
    position: relative;
    overflow: hidden;
  }

  .hud-card::before {
    content: '';
    position: absolute; top: 0; left: 0; right: 0; height: 1px;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.15), transparent);
  }

  /* ─── Compact HUD (active tracking) ─── */
  .compact-hud {
    position: absolute; bottom: 0; left: 0; right: 0;
    z-index: 20;
    padding: 0 10px calc(var(--safe-bottom) + 8px) 10px;
  }

  .compact-strip {
    border-radius: 20px;
    padding: 12px 16px 10px;
    position: relative;
    overflow: hidden;
  }

  .compact-strip::before {
    content: '';
    position: absolute; top: 0; left: 0; right: 0; height: 1px;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.12), transparent);
  }

  .compact-top-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 10px;
  }

  .compact-speed-group {
    display: flex;
    align-items: baseline;
    gap: 5px;
  }

  .compact-speed-value {
    font-size: 44px;
    font-weight: 800;
    letter-spacing: -2px;
    line-height: 1;
    font-variant-numeric: tabular-nums;
    color: #fff;
  }

  .compact-speed-unit {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-tertiary);
    letter-spacing: 0.5px;
    margin-bottom: 3px;
  }

  .compact-stop-btn {
    width: 42px; height: 42px;
    border-radius: 13px;
    border: none;
    cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    background: var(--red-dim);
    color: var(--red);
    font-size: 15px;
    transition: all 0.2s ease;
    flex-shrink: 0;
  }

  .compact-stop-btn:active { transform: scale(0.88); }

  .compact-stats {
    display: flex;
    gap: 0;
  }

  .compact-stat {
    display: flex;
    align-items: center;
    gap: 5px;
    flex: 1;
    justify-content: center;
    padding: 0 2px;
  }

  .compact-stat:not(:last-child) {
    border-right: 1px solid rgba(255,255,255,0.06);
  }

  .compact-stat-icon { font-size: 12px; opacity: 0.7; }

  .compact-stat-val {
    font-size: 14px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--text-primary);
  }

  .compact-stat-lbl {
    font-size: 10px;
    color: var(--text-tertiary);
    margin-left: 1px;
  }

  /* GPS Signal */
  .gps-indicator {
    display: flex; align-items: center; gap: 6px;
    font-size: 11px; font-weight: 500;
    color: var(--text-secondary);
  }

  .gps-dot {
    width: 7px; height: 7px; border-radius: 50%;
    animation: gps-blink 2s ease-in-out infinite;
  }

  @keyframes gps-blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }

  .start-btn {
    background: var(--blue-dim);
    color: var(--blue);
    border: 1px solid rgba(10, 132, 255, 0.2);
  }

  /* ─── Tab Bar (Liquid Glass) ─── */
  .tab-bar {
    position: absolute; bottom: 0; left: 0; right: 0;
    height: calc(54px + var(--safe-bottom));
    padding: 0 40px;
    padding-bottom: var(--safe-bottom);
    display: flex; align-items: center; justify-content: space-around;
    z-index: 50;
    border-top: 1px solid rgba(255,255,255,0.06);
  }

  .tab-item {
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    cursor: pointer; padding: 4px 16px;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    position: relative;
    border: none; background: none; color: inherit; font-family: inherit;
  }

  .tab-icon {
    font-size: 22px; transition: all 0.3s ease;
    opacity: 0.45;
  }

  .tab-item.active .tab-icon { opacity: 1; }

  .tab-label {
    font-size: 10px; font-weight: 500;
    color: var(--text-tertiary);
    transition: all 0.3s ease;
  }

  .tab-item.active .tab-label { color: var(--blue); }

  .tab-active-pill {
    position: absolute; top: -1px; left: 50%; transform: translateX(-50%);
    width: 20px; height: 3px; border-radius: 2px;
    background: var(--blue);
    opacity: 0;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .tab-item.active .tab-active-pill { opacity: 1; }

  /* ─── Screen transitions ─── */
  .screen {
    position: absolute; inset: 0;
    transition: opacity 0.35s ease, transform 0.35s ease;
  }

  .screen-enter { opacity: 0; transform: translateY(8px); }
  .screen-active { opacity: 1; transform: translateY(0); }

  /* ─── Trips List ─── */
  .screen-scroll {
    position: absolute; inset: 0;
    overflow-y: auto;
    padding: calc(var(--safe-top) + 16px) 16px calc(54px + var(--safe-bottom) + 16px);
    background: #000;
    -webkit-overflow-scrolling: touch;
  }

  .screen-scroll::-webkit-scrollbar { display: none; }

  .section-title {
    font-size: 34px;
    font-weight: 800;
    letter-spacing: -0.5px;
    margin-bottom: 8px;
    color: var(--text-primary);
  }

  .section-subtitle {
    font-size: 15px;
    color: var(--text-secondary);
    margin-bottom: 24px;
  }

  .trip-card {
    border-radius: 20px;
    padding: 16px;
    margin-bottom: 12px;
    cursor: pointer;
    transition: all 0.25s ease;
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
    position: relative;
    overflow: hidden;
  }

  .trip-card:active { transform: scale(0.98); background: var(--surface-elevated); }

  .trip-card-map {
    height: 120px;
    border-radius: 14px;
    margin-bottom: 14px;
    overflow: hidden;
    position: relative;
    background:
      radial-gradient(circle at 50% 50%, rgba(10, 132, 255, 0.06) 0%, transparent 70%),
      linear-gradient(135deg, #0d1117, #161b22);
  }

  .trip-card-map svg { width: 100%; height: 100%; }

  .trip-card-date {
    font-size: 13px;
    color: var(--text-secondary);
    margin-bottom: 8px;
  }

  .trip-card-stats {
    display: flex; gap: 16px; align-items: center;
  }

  .trip-stat {
    display: flex; align-items: center; gap: 6px;
    font-size: 15px; font-weight: 600;
  }

  .trip-stat-icon {
    font-size: 13px; opacity: 0.6;
  }

  .trip-card-chevron {
    position: absolute; right: 16px; bottom: 18px;
    color: var(--text-tertiary);
    font-size: 16px;
  }

  /* ─── Trip Detail ─── */
  .detail-header {
    position: relative;
    height: 280px;
    overflow: hidden;
  }

  .detail-map {
    position: absolute; inset: 0;
    background:
      radial-gradient(circle at 50% 50%, rgba(10, 132, 255, 0.1) 0%, transparent 60%),
      linear-gradient(180deg, #0d1117, #161b22);
  }

  .detail-back {
    position: absolute; top: var(--safe-top); left: 16px;
    z-index: 10;
    width: 36px; height: 36px;
    border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer;
    border: none; font-family: inherit;
    background: rgba(28, 28, 30, 0.7);
    backdrop-filter: blur(20px);
    color: var(--blue);
    font-size: 18px;
    border: 1px solid rgba(255,255,255,0.08);
    transition: all 0.2s;
  }

  .detail-back:active { transform: scale(0.9); }

  .detail-content {
    padding: 24px 16px calc(54px + var(--safe-bottom) + 16px);
    background: #000;
  }

  .detail-stat-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    margin-top: 20px;
  }

  .detail-stat-card {
    padding: 16px;
    border-radius: 16px;
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
  }

  .detail-stat-value {
    font-size: 28px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.5px;
  }

  .detail-stat-label {
    font-size: 12px;
    color: var(--text-secondary);
    margin-top: 4px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .detail-action-row {
    display: flex; gap: 10px; margin-top: 20px;
  }

  .detail-action-btn {
    flex: 1;
    padding: 14px;
    border-radius: 14px;
    border: none;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    font-family: inherit;
    display: flex; align-items: center; justify-content: center; gap: 8px;
    transition: all 0.2s ease;
  }

  .detail-action-btn:active { transform: scale(0.97); }

  .detail-action-primary {
    background: var(--blue-dim);
    color: var(--blue);
  }

  .detail-action-secondary {
    background: var(--surface);
    color: var(--text-primary);
    border: 1px solid rgba(255,255,255,0.06);
  }

  /* ─── Scratch Map ─── */
  .scratch-map-container {
    position: relative;
    height: 320px;
    border-radius: 20px;
    overflow: hidden;
    margin-bottom: 20px;
    background:
      radial-gradient(circle at 50% 45%, rgba(10, 132, 255, 0.08) 0%, transparent 60%),
      var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
  }

  .regions-progress {
    padding: 20px;
    border-radius: 20px;
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
    margin-bottom: 16px;
  }

  .progress-bar-track {
    width: 100%;
    height: 6px;
    border-radius: 3px;
    background: rgba(255,255,255,0.06);
    margin-top: 12px;
    overflow: hidden;
  }

  .progress-bar-fill {
    height: 100%;
    border-radius: 3px;
    background: linear-gradient(90deg, var(--blue), var(--teal));
    transition: width 1s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .region-list-item {
    display: flex;
    align-items: center;
    padding: 14px 16px;
    border-radius: 14px;
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
    margin-bottom: 8px;
    cursor: pointer;
    transition: all 0.2s ease;
  }

  .region-list-item:active { background: var(--surface-elevated); }

  .region-dot {
    width: 10px; height: 10px; border-radius: 50%; margin-right: 14px; flex-shrink: 0;
  }

  .region-info { flex: 1; }
  .region-name { font-size: 16px; font-weight: 600; }
  .region-meta { font-size: 13px; color: var(--text-secondary); margin-top: 2px; }
  .region-km { font-size: 15px; font-weight: 600; color: var(--text-secondary); }

  /* ─── Achievements ─── */
  .achievement-card {
    display: flex;
    align-items: center;
    padding: 16px;
    border-radius: 16px;
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
    margin-bottom: 10px;
    transition: all 0.2s;
  }

  .achievement-card.locked { opacity: 0.5; }

  .achievement-icon {
    width: 48px; height: 48px;
    border-radius: 14px;
    display: flex; align-items: center; justify-content: center;
    font-size: 24px;
    margin-right: 14px;
    flex-shrink: 0;
    background: rgba(255,255,255,0.05);
  }

  .achievement-card:not(.locked) .achievement-icon {
    background: var(--blue-dim);
  }

  .achievement-info { flex: 1; }
  .achievement-title { font-size: 16px; font-weight: 600; }
  .achievement-desc { font-size: 13px; color: var(--text-secondary); margin-top: 2px; }

  .achievement-progress {
    width: 100%;
    height: 4px;
    border-radius: 2px;
    background: rgba(255,255,255,0.06);
    margin-top: 8px;
    overflow: hidden;
  }

  .achievement-progress-fill {
    height: 100%;
    border-radius: 2px;
    background: var(--blue);
    transition: width 1s ease;
  }

  .achievement-check {
    color: var(--green);
    font-size: 18px;
    margin-left: 10px;
  }

  /* ─── Start Screen (Idle) ─── */
  .idle-hero {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 40px 24px 24px;
    text-align: center;
  }

  .idle-icon-ring {
    width: 100px; height: 100px;
    border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    margin-bottom: 24px;
    position: relative;
    background: rgba(10, 132, 255, 0.1);
    border: 2px solid rgba(10, 132, 255, 0.2);
  }

  .idle-icon-ring::after {
    content: '';
    position: absolute; inset: -6px;
    border-radius: 50%;
    border: 1px solid rgba(10, 132, 255, 0.08);
    animation: idle-ring 3s ease-in-out infinite;
  }

  @keyframes idle-ring {
    0%, 100% { transform: scale(1); opacity: 0.5; }
    50% { transform: scale(1.1); opacity: 0; }
  }

  .idle-title {
    font-size: 22px;
    font-weight: 700;
    margin-bottom: 8px;
  }

  .idle-desc {
    font-size: 15px;
    color: var(--text-secondary);
    line-height: 1.5;
    margin-bottom: 32px;
  }

  .idle-start-btn {
    width: 100%;
    padding: 18px;
    border-radius: 16px;
    border: none;
    font-size: 18px;
    font-weight: 700;
    cursor: pointer;
    font-family: inherit;
    background: var(--blue);
    color: #fff;
    transition: all 0.25s ease;
    display: flex; align-items: center; justify-content: center; gap: 10px;
    box-shadow: 0 4px 24px rgba(10, 132, 255, 0.3);
  }

  .idle-start-btn:active { transform: scale(0.97); box-shadow: 0 2px 12px rgba(10, 132, 255, 0.2); }

  .quick-stats {
    display: flex; gap: 10px; margin-top: 20px; width: 100%;
  }

  .quick-stat {
    flex: 1;
    padding: 14px 12px;
    border-radius: 14px;
    background: var(--surface);
    border: 1px solid rgba(255,255,255,0.04);
    text-align: center;
  }

  .quick-stat-value {
    font-size: 22px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  .quick-stat-label {
    font-size: 11px;
    color: var(--text-tertiary);
    margin-top: 4px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  /* ─── Shared Animations ─── */
  @keyframes fadeUp {
    from { opacity: 0; transform: translateY(12px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .animate-in { animation: fadeUp 0.5s cubic-bezier(0.4, 0, 0.2, 1) forwards; }
  .delay-1 { animation-delay: 0.05s; opacity: 0; }
  .delay-2 { animation-delay: 0.1s; opacity: 0; }
  .delay-3 { animation-delay: 0.15s; opacity: 0; }
  .delay-4 { animation-delay: 0.2s; opacity: 0; }
  .delay-5 { animation-delay: 0.25s; opacity: 0; }
  .delay-6 { animation-delay: 0.3s; opacity: 0; }

  /* ─── Recenter button ─── */
  .recenter-btn {
    position: absolute; top: calc(var(--safe-top) + 10px); right: 16px;
    width: 40px; height: 40px;
    border-radius: 12px;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer; z-index: 15;
    border: none; font-family: inherit;
    background: rgba(28, 28, 30, 0.7);
    backdrop-filter: blur(20px);
    color: var(--text-primary);
    font-size: 18px;
    border: 1px solid rgba(255,255,255,0.08);
    transition: all 0.2s;
  }

  .recenter-btn:active { transform: scale(0.9); }

  /* ─── Free tier badge ─── */
  .free-badge {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 12px; border-radius: 8px;
    background: var(--orange-dim);
    color: var(--orange);
    font-size: 12px; font-weight: 600;
    margin-bottom: 16px;
  }

  /* Trip detail scroll */
  .detail-scroll {
    position: absolute; inset: 0;
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
    background: #000;
  }
  .detail-scroll::-webkit-scrollbar { display: none; }
`;

// ─── SVG Icons (SF Symbols approximation) ────────────────────────────────
const Icons = {
  location: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/>
    </svg>
  ),
  car: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 17h14v-5l-2-6H7L5 12z"/><circle cx="7.5" cy="17.5" r="1.5"/><circle cx="16.5" cy="17.5" r="1.5"/>
    </svg>
  ),
  map: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/>
    </svg>
  ),
  trophy: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 9H4a2 2 0 01-2-2V5a2 2 0 012-2h2"/><path d="M18 9h2a2 2 0 002-2V5a2 2 0 00-2-2h-2"/>
      <path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20 7 22h10c0-2 -.85-3.25-2.03-3.79A1.07 1.07 0 0114 17v-2.34"/>
      <path d="M18 2H6v7a6 6 0 0012 0V2z"/>
    </svg>
  ),
  settings: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/>
    </svg>
  ),
  chevronLeft: <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M8 2L2 8l6 6"/></svg>,
  chevronRight: <svg width="8" height="14" viewBox="0 0 8 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>,
  crosshair: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="22" y1="12" x2="18" y2="12"/><line x1="6" y1="12" x2="2" y2="12"/><line x1="12" y1="6" x2="12" y2="2"/><line x1="12" y1="22" x2="12" y2="18"/></svg>,
  share: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12v8a2 2 0 002 2h12a2 2 0 002-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>,
  download: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>,
  mountain: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 3l4 8 5-5 5 15H2L8 3z"/></svg>,
  clock: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>,
  pin: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/></svg>,
  check: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>,
};

// ─── Route SVG Generator ─────────────────────────────────────────────────
function RouteSVG({ route, color = "var(--blue)", width = "100%", height = "100%", padding = 20 }) {
  if (!route || route.length < 2) return null;
  const lats = route.map(p => p[0]);
  const lngs = route.map(p => p[1]);
  const minLat = Math.min(...lats), maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
  const rangeX = maxLng - minLng || 0.01;
  const rangeY = maxLat - minLat || 0.01;

  const toX = lng => padding + ((lng - minLng) / rangeX) * (300 - padding * 2);
  const toY = lat => padding + ((maxLat - lat) / rangeY) * (120 - padding * 2);

  const pathData = route.map((p, i) => `${i === 0 ? 'M' : 'L'}${toX(p[1])},${toY(p[0])}`).join(' ');
  const start = route[0];
  const end = route[route.length - 1];

  return (
    <svg width={width} height={height} viewBox="0 0 300 120" preserveAspectRatio="xMidYMid meet">
      <path d={pathData} stroke={color} strokeWidth="8" fill="none" opacity="0.15" strokeLinecap="round" strokeLinejoin="round" />
      <path d={pathData} stroke={color} strokeWidth="3" fill="none" opacity="0.9" strokeLinecap="round" strokeLinejoin="round"
        strokeDasharray="8 4" />
      <circle cx={toX(start[1])} cy={toY(start[0])} r="5" fill="#30D158" opacity="0.9" />
      <circle cx={toX(end[1])} cy={toY(end[0])} r="5" fill="#FF453A" opacity="0.9" />
    </svg>
  );
}

// ─── Russia Map SVG (Simplified) ─────────────────────────────────────────
function RussiaMapSVG({ visited }) {
  const regionPaths = [
    { id: "krasnodar", d: "M120 200 L130 195 L140 198 L145 210 L135 215 L125 212 Z", name: "Краснодарский край" },
    { id: "adygea", d: "M128 205 L135 202 L138 207 L133 210 Z", name: "Адыгея" },
    { id: "rostov", d: "M130 185 L150 180 L158 188 L150 195 L135 192 Z", name: "Ростовская область" },
    { id: "stavropol", d: "M145 200 L160 195 L168 205 L158 212 L148 208 Z", name: "Ставропольский край" },
    { id: "volgograd", d: "M158 175 L175 170 L182 182 L172 190 L160 185 Z", name: "Волгоградская область" },
    { id: "crimea", d: "M110 205 L120 200 L118 215 L108 212 Z", name: "Крым" },
    { id: "kcherkesia", d: "M148 210 L155 208 L158 215 L152 218 Z", name: "Карачаево-Черкесия" },
    { id: "kbalkaria", d: "M155 210 L162 208 L165 215 L158 218 Z", name: "Кабардино-Балкария" },
    { id: "moscow", d: "M155 140 L165 135 L172 142 L168 150 L158 148 Z", name: "Москва" },
    { id: "spb", d: "M150 105 L158 100 L165 108 L160 115 L152 112 Z", name: "Санкт-Петербург" },
    { id: "novosibirsk", d: "M240 145 L258 140 L265 150 L255 158 L242 152 Z", name: "Новосибирская область" },
    { id: "altai", d: "M248 158 L260 155 L265 165 L255 170 L250 165 Z", name: "Алтай" },
    { id: "irkutsk", d: "M280 140 L298 135 L305 148 L295 155 L282 148 Z", name: "Иркутская область" },
    { id: "samara", d: "M180 155 L195 150 L200 162 L192 168 L182 162 Z", name: "Самарская область" },
    { id: "tatarstan", d: "M178 140 L190 135 L198 145 L190 152 L180 148 Z", name: "Татарстан" },
    { id: "sverdlovsk", d: "M205 125 L220 120 L228 132 L218 140 L208 135 Z", name: "Свердловская область" },
    { id: "chelyabinsk", d: "M210 140 L225 135 L230 148 L222 155 L212 148 Z", name: "Челябинская область" },
  ];

  const visitedNames = visited.map(r => r.name);

  return (
    <svg width="100%" height="100%" viewBox="90 80 240 160" preserveAspectRatio="xMidYMid meet">
      <defs>
        <linearGradient id="visitedGrad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#0A84FF" />
          <stop offset="100%" stopColor="#64D2FF" />
        </linearGradient>
      </defs>
      {regionPaths.map(region => {
        const isVisited = visitedNames.includes(region.name);
        const regionData = visited.find(r => r.name === region.name);
        return (
          <path
            key={region.id}
            d={region.d}
            fill={isVisited ? `rgba(10, 132, 255, ${0.2 + (regionData?.intensity || 0) * 0.6})` : "rgba(255,255,255,0.04)"}
            stroke={isVisited ? "rgba(10, 132, 255, 0.5)" : "rgba(255,255,255,0.08)"}
            strokeWidth="0.5"
            style={{ transition: "all 0.5s ease" }}
          />
        );
      })}
    </svg>
  );
}

// ─── Main Tracking Route SVG ─────────────────────────────────────────────
function LiveRouteSVG() {
  return (
    <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }}>
      <defs>
        <linearGradient id="routeGrad" x1="0%" y1="100%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="#0A84FF" stopOpacity="0.6" />
          <stop offset="50%" stopColor="#30D158" stopOpacity="0.7" />
          <stop offset="100%" stopColor="#64D2FF" stopOpacity="0.9" />
        </linearGradient>
      </defs>
      {/* Wide glow */}
      <path d="M30 780 Q60 700 80 620 Q100 540 130 470 Q165 390 190 340 Q220 280 260 230 Q295 185 330 150"
        stroke="rgba(10,132,255,0.08)" strokeWidth="28" fill="none" strokeLinecap="round" />
      {/* Medium glow */}
      <path d="M30 780 Q60 700 80 620 Q100 540 130 470 Q165 390 190 340 Q220 280 260 230 Q295 185 330 150"
        stroke="rgba(10,132,255,0.12)" strokeWidth="12" fill="none" strokeLinecap="round" />
      {/* Main line */}
      <path d="M30 780 Q60 700 80 620 Q100 540 130 470 Q165 390 190 340 Q220 280 260 230 Q295 185 330 150"
        stroke="url(#routeGrad)" strokeWidth="3.5" fill="none" strokeLinecap="round" />
      {/* Thin bright edge */}
      <path d="M30 780 Q60 700 80 620 Q100 540 130 470 Q165 390 190 340 Q220 280 260 230 Q295 185 330 150"
        stroke="rgba(100,210,255,0.25)" strokeWidth="1" fill="none" strokeLinecap="round" />
      {/* Start dot */}
      <circle cx="30" cy="780" r="4" fill="#30D158" opacity="0.6" />
    </svg>
  );
}


// ─── SCREENS ─────────────────────────────────────────────────────────────

// 1. TRACKING SCREEN (Active)
function TrackingScreen({ isTracking, onToggle }) {
  const [speed, setSpeed] = useState(87);
  const [altitude, setAltitude] = useState(342);
  const [time, setTime] = useState({ h: 1, m: 24, s: 37 });
  const [distance, setDistance] = useState(45.2);
  const [gpsQuality, setGpsQuality] = useState("good");

  useEffect(() => {
    if (!isTracking) return;
    const interval = setInterval(() => {
      setSpeed(prev => Math.max(0, Math.min(180, prev + (Math.random() - 0.48) * 8)));
      setAltitude(prev => Math.max(0, prev + (Math.random() - 0.5) * 5));
      setDistance(prev => prev + 0.01 + Math.random() * 0.02);
      setTime(prev => {
        let s = prev.s + 1;
        let m = prev.m;
        let h = prev.h;
        if (s >= 60) { s = 0; m++; }
        if (m >= 60) { m = 0; h++; }
        return { h, m, s };
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [isTracking]);

  if (!isTracking) {
    return (
      <div style={{ position: "absolute", inset: 0 }}>
        <div className="map-bg">
          <div className="map-grid" />
        </div>
        <div className="hud-panel">
          <div className="hud-card glass animate-in">
            <div className="idle-hero">
              <div className="idle-icon-ring">
                <span style={{ fontSize: 36 }}>🚗</span>
              </div>
              <div className="idle-title">Готов к поездке</div>
              <div className="idle-desc">Нажмите кнопку или начните движение — трекинг запустится автоматически</div>
              <button className="idle-start-btn" onClick={onToggle}>
                <span>◉</span> Начать поездку
              </button>
              <div className="quick-stats">
                <div className="quick-stat">
                  <div className="quick-stat-value" style={{ color: "var(--blue)" }}>3 890</div>
                  <div className="quick-stat-label">км всего</div>
                </div>
                <div className="quick-stat">
                  <div className="quick-stat-value" style={{ color: "var(--green)" }}>23</div>
                  <div className="quick-stat-label">поездки</div>
                </div>
                <div className="quick-stat">
                  <div className="quick-stat-value" style={{ color: "var(--orange)" }}>8</div>
                  <div className="quick-stat-label">регионов</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {/* Map Background — full screen */}
      <div className="map-bg">
        <div className="map-grid" />
        {/* Secondary roads / terrain hints */}
        <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: 0.06 }}>
          <path d="M0 400 Q100 380 200 420 Q300 460 393 440" stroke="#fff" strokeWidth="1" fill="none" />
          <path d="M0 300 Q150 280 250 320 Q350 360 393 340" stroke="#fff" strokeWidth="0.5" fill="none" />
          <path d="M100 0 Q120 200 90 400 Q70 600 100 852" stroke="#fff" strokeWidth="0.5" fill="none" />
          <path d="M250 0 Q230 150 270 300 Q300 450 280 600 Q260 750 300 852" stroke="#fff" strokeWidth="0.5" fill="none" />
          <path d="M0 550 Q100 530 200 560 Q300 590 393 570" stroke="#fff" strokeWidth="0.5" fill="none" />
          <path d="M180 0 Q190 100 170 200 Q160 300 180 400" stroke="#fff" strokeWidth="0.3" fill="none" />
          {/* Terrain hints */}
          <circle cx="80" cy="250" r="40" fill="rgba(48,209,88,0.15)" />
          <circle cx="320" cy="400" r="55" fill="rgba(48,209,88,0.08)" />
          <circle cx="200" cy="150" r="30" fill="rgba(10,132,255,0.06)" />
        </svg>
        <LiveRouteSVG />
      </div>

      {/* Current position — at route head, centered in visible map */}
      <div className="current-pos" style={{ top: "18%", left: "82%" }} />

      {/* GPS Quality — top left pill */}
      <div className="glass-pill" style={{ position: "absolute", top: `calc(var(--safe-top) + 10px)`, left: 12, zIndex: 15, display: "flex", alignItems: "center", gap: 6 }}>
        <div className="gps-dot" style={{ background: gpsQuality === "good" ? "var(--green)" : "var(--orange)" }} />
        <span style={{ fontSize: 12, fontWeight: 500 }}>{gpsQuality === "good" ? "±5м" : "±25м"}</span>
      </div>

      {/* Recenter button — top right */}
      <button className="recenter-btn glass" style={{ top: `calc(var(--safe-top) + 8px)` }}>
        {Icons.crosshair}
      </button>

      {/* ─── Compact HUD Strip ─── */}
      <div className="compact-hud">
        <div className="compact-strip glass animate-in">

          {/* Top: speed + stop button */}
          <div className="compact-top-row">
            <div className="compact-speed-group">
              <div className="compact-speed-value">{Math.round(speed)}</div>
              <div className="compact-speed-unit">км/ч</div>
            </div>
            <button className="compact-stop-btn" onClick={onToggle}>◼</button>
          </div>

          {/* Bottom: stats row */}
          <div className="compact-stats">
            <div className="compact-stat">
              <span className="compact-stat-icon" style={{ color: "var(--blue)" }}>⛰</span>
              <span className="compact-stat-val">{Math.round(altitude)}</span>
              <span className="compact-stat-lbl">м</span>
            </div>
            <div className="compact-stat">
              <span className="compact-stat-icon" style={{ color: "var(--orange)" }}>⏱</span>
              <span className="compact-stat-val">{time.h}:{String(time.m).padStart(2, "0")}</span>
            </div>
            <div className="compact-stat">
              <span className="compact-stat-icon" style={{ color: "var(--green)" }}>📍</span>
              <span className="compact-stat-val">{distance.toFixed(1)}</span>
              <span className="compact-stat-lbl">км</span>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}

// 2. TRIPS LIST SCREEN
function TripsScreen({ onSelectTrip }) {
  return (
    <div className="screen-scroll">
      <div className="animate-in">
        <div className="free-badge">⚡ Использовано 3/10 поездок</div>
        <div className="section-title">Поездки</div>
        <div className="section-subtitle">История ваших путешествий</div>
      </div>

      {MOCK_TRIPS.map((trip, i) => (
        <div
          key={trip.id}
          className={`trip-card animate-in delay-${i + 1}`}
          onClick={() => onSelectTrip(trip)}
        >
          <div className="trip-card-map">
            <RouteSVG route={trip.route} />
          </div>
          <div className="trip-card-date">{trip.date}, {trip.time}</div>
          <div className="trip-card-stats">
            <div className="trip-stat">
              <span className="trip-stat-icon" style={{ color: "var(--green)" }}>📍</span>
              {trip.distance} км
            </div>
            <div className="trip-stat">
              <span className="trip-stat-icon" style={{ color: "var(--orange)" }}>⏱</span>
              {trip.duration}
            </div>
            {trip.regions.length > 1 && (
              <div className="trip-stat" style={{ color: "var(--text-secondary)", fontSize: 13 }}>
                <span className="trip-stat-icon" style={{ color: "var(--blue)" }}>🗺</span>
                {trip.regions.length} рег.
              </div>
            )}
          </div>
          <div className="trip-card-chevron" style={{ color: "var(--text-tertiary)" }}>
            {Icons.chevronRight}
          </div>
        </div>
      ))}

      <div style={{ height: 20 }} />
    </div>
  );
}

// 3. TRIP DETAIL SCREEN
function TripDetailScreen({ trip, onBack }) {
  if (!trip) return null;

  return (
    <div className="detail-scroll">
      {/* Map header */}
      <div className="detail-header">
        <div className="detail-map">
          <div className="map-grid" style={{ opacity: 0.03 }} />
          <div style={{ padding: 30, height: "100%", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <RouteSVG route={trip.route} width="100%" height="100%" padding={30} />
          </div>
        </div>
        <button className="detail-back" onClick={onBack}>
          {Icons.chevronLeft}
        </button>
      </div>

      {/* Content */}
      <div className="detail-content">
        <div className="animate-in">
          <div style={{ fontSize: 13, color: "var(--text-secondary)", marginBottom: 4 }}>{trip.date}</div>
          <div style={{ fontSize: 24, fontWeight: 700 }}>Поездка {trip.time}</div>
          {trip.regions.length > 0 && (
            <div style={{ display: "flex", gap: 6, marginTop: 10, flexWrap: "wrap" }}>
              {trip.regions.map(r => (
                <span key={r} className="glass-pill" style={{ fontSize: 12 }}>📍 {r}</span>
              ))}
            </div>
          )}
        </div>

        <div className="detail-stat-grid animate-in delay-1">
          <div className="detail-stat-card">
            <div className="detail-stat-value" style={{ color: "var(--green)" }}>{trip.distance}</div>
            <div className="detail-stat-label">км пройдено</div>
          </div>
          <div className="detail-stat-card">
            <div className="detail-stat-value" style={{ color: "var(--orange)" }}>{trip.duration}</div>
            <div className="detail-stat-label">время в пути</div>
          </div>
          <div className="detail-stat-card">
            <div className="detail-stat-value" style={{ color: "var(--blue)" }}>{trip.avgSpeed}</div>
            <div className="detail-stat-label">км/ч средняя</div>
          </div>
          <div className="detail-stat-card">
            <div className="detail-stat-value" style={{ color: "var(--red)" }}>{trip.maxSpeed}</div>
            <div className="detail-stat-label">км/ч макс.</div>
          </div>
        </div>

        <div className="detail-action-row animate-in delay-2">
          <button className="detail-action-btn detail-action-primary">
            {Icons.share} Поделиться
          </button>
          <button className="detail-action-btn detail-action-secondary">
            {Icons.download} GPX
            <span style={{ fontSize: 10, background: "var(--purple-dim)", color: "var(--purple)", padding: "2px 6px", borderRadius: 4, marginLeft: 4 }}>PRO</span>
          </button>
        </div>
      </div>
    </div>
  );
}

// 4. REGIONS SCREEN (Scratch Map + Achievements)
function RegionsScreen() {
  const [activeTab, setActiveTab] = useState("map");
  const totalRegions = 85;
  const visitedCount = REGIONS_DATA.length;
  const percentage = Math.round((visitedCount / totalRegions) * 100);

  return (
    <div className="screen-scroll">
      <div className="animate-in">
        <div className="section-title">Карта</div>
        <div className="section-subtitle">Посещённые регионы и достижения</div>
      </div>

      {/* Tabs */}
      <div style={{ display: "flex", gap: 8, marginBottom: 20 }} className="animate-in delay-1">
        <button className={`glass-pill ${activeTab === "map" ? "active" : ""}`} onClick={() => setActiveTab("map")} style={{ cursor: "pointer", border: activeTab === "map" ? "1px solid rgba(10,132,255,0.3)" : undefined, background: activeTab === "map" ? "rgba(10,132,255,0.15)" : undefined, color: activeTab === "map" ? "var(--blue)" : undefined }}>
          🗺 Регионы
        </button>
        <button className={`glass-pill ${activeTab === "achievements" ? "active" : ""}`} onClick={() => setActiveTab("achievements")} style={{ cursor: "pointer", border: activeTab === "achievements" ? "1px solid rgba(10,132,255,0.3)" : undefined, background: activeTab === "achievements" ? "rgba(10,132,255,0.15)" : undefined, color: activeTab === "achievements" ? "var(--blue)" : undefined }}>
          🏆 Достижения
        </button>
        <button className={`glass-pill ${activeTab === "stats" ? "active" : ""}`} onClick={() => setActiveTab("stats")} style={{ cursor: "pointer", border: activeTab === "stats" ? "1px solid rgba(10,132,255,0.3)" : undefined, background: activeTab === "stats" ? "rgba(10,132,255,0.15)" : undefined, color: activeTab === "stats" ? "var(--blue)" : undefined }}>
          📊 Статистика
        </button>
      </div>

      {activeTab === "map" && (
        <>
          {/* Scratch Map */}
          <div className="scratch-map-container animate-in delay-2">
            <RussiaMapSVG visited={REGIONS_DATA} />
          </div>

          {/* Progress */}
          <div className="regions-progress animate-in delay-3">
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <div>
                <span style={{ fontSize: 28, fontWeight: 700, color: "var(--blue)" }}>{visitedCount}</span>
                <span style={{ fontSize: 15, color: "var(--text-secondary)" }}> / {totalRegions} регионов</span>
              </div>
              <span style={{ fontSize: 15, fontWeight: 600, color: "var(--text-secondary)" }}>{percentage}%</span>
            </div>
            <div className="progress-bar-track">
              <div className="progress-bar-fill" style={{ width: `${percentage}%` }} />
            </div>
            <div style={{ marginTop: 10, fontSize: 13, color: "var(--text-tertiary)" }}>
              🏆 Ранг: <span style={{ color: "var(--orange)", fontWeight: 600 }}>Исследователь</span>
            </div>
          </div>

          {/* Region list */}
          {REGIONS_DATA.sort((a, b) => b.km - a.km).map((region, i) => (
            <div key={region.name} className={`region-list-item animate-in delay-${Math.min(i + 3, 6)}`}>
              <div className="region-dot" style={{ background: `rgba(10, 132, 255, ${0.3 + region.intensity * 0.7})` }} />
              <div className="region-info">
                <div className="region-name">{region.name}</div>
                <div className="region-meta">{region.trips} поездок · с {new Date(region.firstVisit).toLocaleDateString("ru-RU", { month: "short", year: "numeric" })}</div>
              </div>
              <div className="region-km">{region.km} км</div>
            </div>
          ))}
        </>
      )}

      {activeTab === "achievements" && (
        <>
          {ACHIEVEMENTS.map((ach, i) => (
            <div key={ach.id} className={`achievement-card animate-in delay-${Math.min(i + 1, 6)} ${!ach.unlocked ? "locked" : ""}`}>
              <div className="achievement-icon">{ach.icon}</div>
              <div className="achievement-info">
                <div className="achievement-title">{ach.title}</div>
                <div className="achievement-desc">{ach.desc}</div>
                {!ach.unlocked && (
                  <div className="achievement-progress">
                    <div className="achievement-progress-fill" style={{ width: `${(ach.progress / ach.total) * 100}%` }} />
                  </div>
                )}
                {!ach.unlocked && (
                  <div style={{ fontSize: 11, color: "var(--text-tertiary)", marginTop: 4 }}>
                    {ach.progress.toLocaleString()} / {ach.total.toLocaleString()}
                  </div>
                )}
              </div>
              {ach.unlocked && (
                <div className="achievement-check">{Icons.check}</div>
              )}
            </div>
          ))}
        </>
      )}

      {activeTab === "stats" && (
        <div className="animate-in delay-1">
          <div className="detail-stat-grid">
            <div className="detail-stat-card">
              <div className="detail-stat-value" style={{ color: "var(--blue)" }}>3 890</div>
              <div className="detail-stat-label">км всего</div>
            </div>
            <div className="detail-stat-card">
              <div className="detail-stat-value" style={{ color: "var(--green)" }}>23</div>
              <div className="detail-stat-label">поездок</div>
            </div>
            <div className="detail-stat-card">
              <div className="detail-stat-value" style={{ color: "var(--orange)" }}>312.7</div>
              <div className="detail-stat-label">км макс. поездка</div>
            </div>
            <div className="detail-stat-card">
              <div className="detail-stat-value" style={{ color: "var(--purple)" }}>62</div>
              <div className="detail-stat-label">км/ч средняя</div>
            </div>
          </div>

          {/* Weekly graph mock */}
          <div style={{ marginTop: 20, padding: 20, borderRadius: 20, background: "var(--surface)", border: "1px solid rgba(255,255,255,0.04)" }}>
            <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 16 }}>Километры за неделю</div>
            <div style={{ display: "flex", alignItems: "flex-end", gap: 8, height: 120 }}>
              {[45, 0, 87, 23, 145, 0, 234].map((val, i) => (
                <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                  <div style={{
                    width: "100%",
                    height: Math.max(4, (val / 250) * 100),
                    borderRadius: 6,
                    background: val > 0 ? `rgba(10, 132, 255, ${0.3 + (val / 250) * 0.7})` : "rgba(255,255,255,0.04)",
                    transition: "height 0.5s ease",
                  }} />
                  <span style={{ fontSize: 10, color: "var(--text-tertiary)" }}>
                    {["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"][i]}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      <div style={{ height: 20 }} />
    </div>
  );
}


// ─── MAIN APP ────────────────────────────────────────────────────────────
export default function RoadTripTracker() {
  const [activeTab, setActiveTab] = useState(0);
  const [isTracking, setIsTracking] = useState(true);
  const [selectedTrip, setSelectedTrip] = useState(null);

  const tabs = [
    { label: "Трекинг", icon: "◎" },
    { label: "Поездки", icon: "☰" },
    { label: "Карта", icon: "◇" },
  ];

  return (
    <div style={{ display: "flex", justifyContent: "center", alignItems: "center", minHeight: "100vh", background: "#0a0a0a", padding: 20 }}>
      <style>{styles}</style>

      <div className="phone-frame">
        {/* Dynamic Island */}
        <div className="dynamic-island" />

        {/* Status Bar */}
        <div className="status-bar">
          <span>9:41</span>
          <div className="status-bar-icons">
            <svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor"><rect x="0" y="3" width="3" height="9" rx="1" opacity="0.3"/><rect x="4.5" y="2" width="3" height="10" rx="1" opacity="0.5"/><rect x="9" y="1" width="3" height="11" rx="1" opacity="0.7"/><rect x="13.5" y="0" width="3" height="12" rx="1"/></svg>
            <svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor"><path d="M8 2.4C5.6 2.4 3.4 3.3 1.8 4.8L0 3C2 1.1 4.8 0 8 0s6 1.1 8 3l-1.8 1.8C12.6 3.3 10.4 2.4 8 2.4zM8 7.2c-1.4 0-2.7.5-3.6 1.4L2.6 6.8C3.9 5.6 5.9 4.8 8 4.8s4.1.8 5.4 2l-1.8 1.8C10.7 7.7 9.4 7.2 8 7.2z"/><circle cx="8" cy="11" r="1.5"/></svg>
            <svg width="27" height="12" viewBox="0 0 27 12" fill="currentColor"><rect x="0" y="1" width="23" height="10" rx="2.5" stroke="currentColor" strokeWidth="1" fill="none" opacity="0.35"/><rect x="24" y="3.5" width="2" height="5" rx="1" opacity="0.35"/><rect x="1.5" y="2.5" width="17" height="7" rx="1.5" fill="var(--green)"/></svg>
          </div>
        </div>

        {/* Screens */}
        {activeTab === 0 && !selectedTrip && (
          <TrackingScreen isTracking={isTracking} onToggle={() => setIsTracking(prev => !prev)} />
        )}

        {activeTab === 1 && !selectedTrip && (
          <TripsScreen onSelectTrip={(trip) => setSelectedTrip(trip)} />
        )}

        {activeTab === 2 && !selectedTrip && (
          <RegionsScreen />
        )}

        {/* Trip Detail Overlay */}
        {selectedTrip && (
          <div style={{ position: "absolute", inset: 0, zIndex: 60, background: "#000" }}>
            <TripDetailScreen trip={selectedTrip} onBack={() => setSelectedTrip(null)} />
          </div>
        )}

        {/* Tab Bar (Liquid Glass) — hidden during active tracking */}
        {!selectedTrip && !(activeTab === 0 && isTracking) && (
          <div className="tab-bar glass">
            {tabs.map((tab, i) => (
              <button
                key={i}
                className={`tab-item ${activeTab === i ? "active" : ""}`}
                onClick={() => setActiveTab(i)}
              >
                <div className="tab-active-pill" />
                <span className="tab-icon" style={{ color: activeTab === i ? "var(--blue)" : "var(--text-tertiary)" }}>
                  {tab.icon}
                </span>
                <span className="tab-label">{tab.label}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
