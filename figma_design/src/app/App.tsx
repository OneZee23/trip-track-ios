import { LockScreen } from './components/LockScreen';
import { LiveActivityWidget } from './components/LiveActivityWidget';

export default function App() {
  return (
    <div className="min-h-screen bg-neutral-950 flex flex-col items-center justify-center p-8 font-sans selection:bg-blue-500/30">
      <div className="mb-8 text-center max-w-md">
        <h1 className="text-3xl font-bold text-white mb-2 tracking-tight">TripTrack Widget</h1>
        <p className="text-white/60 text-sm leading-relaxed">
          Интерактивный симулятор Live Activity. Наблюдайте за поездкой, ставьте на паузу или завершайте её, чтобы увидеть результаты и сохранить данные в автодневник.
        </p>
      </div>
      <LockScreen>
        <LiveActivityWidget />
      </LockScreen>
    </div>
  );
}