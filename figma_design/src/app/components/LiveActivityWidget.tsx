import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Pause, Play, Square, CarFront, CheckCircle, ChevronRight } from 'lucide-react';
import carImage from 'figma:asset/badf106c1573605b15e93cb587b72b7149aebcbb.png';

export function LiveActivityWidget() {
  const [state, setState] = useState<'tracking' | 'paused' | 'finished'>('tracking');
  const [distance, setDistance] = useState(0);
  const [time, setTime] = useState(0);

  // Simulation effect for tracking
  useEffect(() => {
    let interval: ReturnType<typeof setInterval>;
    if (state === 'tracking') {
      interval = setInterval(() => {
        setTime((t) => t + 1);
        setDistance((d) => d + 0.02);
      }, 1000);
    }
    return () => clearInterval(interval);
  }, [state]);

  const formatTime = (secs: number) => {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  const handlePause = () => setState('paused');
  const handleResume = () => setState('tracking');
  const handleStop = () => setState('finished');

  return (
    <motion.div
      layout
      transition={{ type: 'spring', bounce: 0.2, duration: 0.6 }}
      className="w-full max-w-[360px] mx-auto bg-[#F2F2F7]/95 backdrop-blur-2xl border border-white/20 p-4 shadow-2xl relative overflow-hidden text-black"
      style={{ borderRadius: 32 }}
    >
      <AnimatePresence mode="wait">
        {state !== 'finished' ? (
          <motion.div
            key="active-state"
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95, filter: 'blur(4px)' }}
            transition={{ duration: 0.3 }}
            className="flex flex-col"
          >
            {/* Header: App Info & Vehicle */}
            <div className="flex justify-between items-start mb-5">
              <div className="flex items-center gap-3.5">
                <div className="w-[44px] h-[44px] rounded-[14px] bg-[#FF9500]/10 flex items-center justify-center shadow-sm relative overflow-hidden border border-[#FF9500]/20">
                  <img src={carImage} alt="Car" className="w-[36px] h-[36px] object-contain" />
                </div>
                <div className="flex flex-col justify-center">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-[16px] leading-tight text-black/90">
                      {state === 'tracking' ? 'Запись маршрута' : 'На паузе'}
                    </span>
                    {state === 'tracking' && (
                      <span className="w-2 h-2 rounded-full bg-[#FF3B30] animate-pulse" />
                    )}
                  </div>
                  <div className="flex items-center gap-1.5 mt-0.5 text-black/50">
                    <CarFront className="w-[14px] h-[14px]" strokeWidth={2.5} />
                    <span className="text-[14px] font-medium">
                      Toyota Camry
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Middle: Open-ended Stats Display */}
            <div className="grid grid-cols-2 gap-3 mb-4">
              <div className="bg-black/[0.04] rounded-[20px] p-4 flex flex-col items-center justify-center border border-black/[0.02]">
                <span className="text-[11px] font-bold text-black/40 uppercase tracking-wider mb-1.5">
                  Время в пути
                </span>
                <span className="text-[26px] font-bold leading-none tabular-nums text-black/80 tracking-tight">
                  {formatTime(time)}
                </span>
              </div>
              <div className="bg-black/[0.04] rounded-[20px] p-4 flex flex-col items-center justify-center border border-black/[0.02]">
                <span className="text-[11px] font-bold text-black/40 uppercase tracking-wider mb-1.5">
                  Пройдено
                </span>
                <div className="flex items-baseline gap-1">
                  <span className="text-[26px] font-bold leading-none tabular-nums text-black/80 tracking-tight">
                    {distance.toFixed(1)}
                  </span>
                  <span className="text-[14px] font-semibold text-black/50">км</span>
                </div>
              </div>
            </div>

            {/* Bottom: Controls */}
            <div className="flex gap-2.5">
              <button
                onClick={state === 'tracking' ? handlePause : handleResume}
                className="flex-1 bg-black/[0.06] hover:bg-black/10 py-3.5 rounded-[20px] text-[15px] font-semibold flex items-center justify-center gap-2.5 text-black/80 transition-colors active:scale-95"
              >
                {state === 'tracking' ? (
                  <>
                    <Pause className="w-[18px] h-[18px]" fill="currentColor" /> Пауза
                  </>
                ) : (
                  <>
                    <Play className="w-[18px] h-[18px]" fill="currentColor" /> Продолжить
                  </>
                )}
              </button>
              <button
                onClick={handleStop}
                className="w-[72px] bg-[#FF3B30]/10 hover:bg-[#FF3B30]/20 text-[#FF3B30] rounded-[20px] flex items-center justify-center transition-colors active:scale-95"
              >
                <Square className="w-[18px] h-[18px]" fill="currentColor" />
              </button>
            </div>
          </motion.div>
        ) : (
          <motion.div
            key="finished-state"
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4, delay: 0.1 }}
            className="flex flex-col items-center pt-3 pb-1 px-1"
          >
            <div className="w-14 h-14 rounded-[20px] bg-[#FF9500]/10 flex items-center justify-center mb-4 border border-[#FF9500]/20">
              <CheckCircle className="w-7 h-7 text-[#FF9500]" strokeWidth={2.5} />
            </div>
            <h3 className="text-[22px] font-bold tracking-tight text-black/90 mb-1.5">Маршрут сохранен</h3>
            <p className="text-[15px] text-black/50 font-medium mb-6">
              Toyota Camry • {distance.toFixed(1)} км • {formatTime(time)}
            </p>
            
            <button
              onClick={() => {
                setState('tracking');
                setDistance(0);
                setTime(0);
              }}
              className="w-full bg-[#FF9500] hover:bg-[#E08300] text-white rounded-[20px] py-4 px-5 flex items-center justify-between font-semibold text-[16px] transition-all active:scale-[0.98] shadow-sm"
            >
              <span>Открыть автодневник</span>
              <div className="w-7 h-7 rounded-full bg-white/20 flex items-center justify-center">
                <ChevronRight className="w-4 h-4" />
              </div>
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}