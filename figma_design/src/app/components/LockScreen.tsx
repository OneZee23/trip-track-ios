import { Signal, Wifi, Battery, Flashlight, Camera } from 'lucide-react';
import { ReactNode } from 'react';

interface LockScreenProps {
  children: ReactNode;
}

export function LockScreen({ children }: LockScreenProps) {
  return (
    <div className="relative w-full max-w-[390px] h-[844px] rounded-[55px] overflow-hidden border-[12px] border-black bg-zinc-900 shadow-2xl mx-auto flex flex-col items-center ring-1 ring-white/10">
      {/* Background Image */}
      <img
        src="https://images.unsplash.com/photo-1545175095-7f8a5fb446c2?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w3Nzg4Nzd8MHwxfHNlYXJjaHwxfHxkYXJrJTIwZm9yZXN0JTIwcm9hZCUyMHJhaW58ZW58MXx8fHwxNzc0NjE5NTQ3fDA&ixlib=rb-4.1.0&q=80&w=1080"
        alt="Wallpaper"
        className="absolute inset-0 w-full h-full object-cover"
      />
      
      {/* Top Bar Status */}
      <div className="absolute top-0 w-full px-7 py-3 flex justify-between items-center text-white z-10">
        <span className="text-[15px] font-semibold tracking-wide">16:49</span>
        <div className="flex gap-2 items-center">
          <Signal className="w-4 h-4 fill-white" />
          <Wifi className="w-4 h-4" />
          <Battery className="w-6 h-6" />
        </div>
      </div>

      {/* Clock and Date */}
      <div className="relative z-10 flex flex-col items-center mt-20 text-white drop-shadow-lg">
        <span className="text-[22px] font-semibold mb-[-8px] text-white/90">Пт, 27 марта</span>
        <h1 className="text-[96px] font-bold tracking-tighter leading-none text-white/95" style={{ fontFamily: 'system-ui, sans-serif' }}>16:49</h1>
      </div>

      {/* Widget Container - bottom anchored */}
      <div className="absolute bottom-[140px] w-full px-4 z-20 flex flex-col gap-4">
        {children}
      </div>

      {/* Bottom Lock Screen Controls */}
      <div className="absolute bottom-12 w-full px-12 flex justify-between z-10">
        <button className="w-[50px] h-[50px] rounded-[25px] bg-black/40 backdrop-blur-xl flex items-center justify-center text-white shadow-sm border border-white/10 transition-transform active:scale-95">
          <Flashlight className="w-6 h-6" strokeWidth={1.5} />
        </button>
        <button className="w-[50px] h-[50px] rounded-[25px] bg-black/40 backdrop-blur-xl flex items-center justify-center text-white shadow-sm border border-white/10 transition-transform active:scale-95">
          <Camera className="w-6 h-6" strokeWidth={1.5} />
        </button>
      </div>

      {/* Home Indicator */}
      <div className="absolute bottom-2 w-[140px] h-1.5 bg-white rounded-full z-10" />
    </div>
  );
}