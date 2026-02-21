import { motion, AnimatePresence } from "motion/react";
import { useNavigate } from "react-router";
import { ArrowLeft, Crosshair, Camera, Pencil, Pause, Check } from "lucide-react";
import { useState } from "react";
import { AddMemoryModal } from "../components/AddMemoryModal";
import { ShareRouteModal } from "../components/ShareRouteModal";

export function Tracking() {
  const navigate = useNavigate();
  const [showAddMemory, setShowAddMemory] = useState(false);
  const [showShareRoute, setShowShareRoute] = useState(false);
  const [isPaused, setIsPaused] = useState(false);

  return (
    <div className="relative min-h-screen bg-[#F5F5F3]">
      {/* Map Background - Minimalist placeholder */}
      <div className="absolute inset-0 bg-[#F5F5F3]">
        <div className="absolute inset-0 opacity-[0.03]">
          {/* Minimalist grid pattern */}
          <div className="w-full h-full" style={{
            backgroundImage: `repeating-linear-gradient(0deg, transparent, transparent 60px, rgba(0,0,0,0.5) 60px, rgba(0,0,0,0.5) 61px),
                             repeating-linear-gradient(90deg, transparent, transparent 60px, rgba(0,0,0,0.5) 60px, rgba(0,0,0,0.5) 61px)`
          }} />
        </div>
      </div>

      {/* Header */}
      <motion.div
        initial={{ y: -100, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.5 }}
        className="absolute top-6 left-0 right-0 px-6 z-10"
      >
        <div className="bg-white/95 backdrop-blur-2xl rounded-[32px] shadow-[0_8px_40px_rgba(0,0,0,0.06)] px-6 py-4 flex items-center justify-between">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={() => navigate("/")}
            className="flex items-center gap-2 p-2 rounded-full hover:bg-black/5 transition-all"
          >
            <ArrowLeft className="w-5 h-5 stroke-[1.5]" />
            <span className="font-black text-sm tracking-tight uppercase">Back</span>
          </motion.button>
          <h2 className="text-lg font-black tracking-tight uppercase">London</h2>
          <div className="w-20" />
        </div>
      </motion.div>

      {/* Current Location Marker - 8-bit Pixel Character */}
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ delay: 0.3, type: "spring", stiffness: 200 }}
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-20"
      >
        <motion.div
          animate={{
            y: [0, -8, 0],
          }}
          transition={{
            duration: 2,
            repeat: Infinity,
            ease: "easeInOut",
          }}
          className="w-16 h-16 rounded-full bg-[#52B788] shadow-[0_8px_32px_rgba(82,183,136,0.25)] flex items-center justify-center"
        >
          {/* 8-bit pixel character */}
          <div className="text-3xl">👧</div>
        </motion.div>
        {/* Subtle pulse ring */}
        <motion.div
          animate={{
            scale: [1, 1.6, 1],
            opacity: [0.25, 0, 0.25],
          }}
          transition={{
            duration: 2,
            repeat: Infinity,
          }}
          className="absolute inset-0 rounded-full bg-[#52B788]"
        />
      </motion.div>

      {/* Right Side Controls */}
      <motion.div
        initial={{ x: 100, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        transition={{ delay: 0.4, duration: 0.5 }}
        className="absolute right-6 top-1/2 -translate-y-1/2 z-10 flex flex-col gap-4"
      >
        <FloatingButton
          icon={<Crosshair className="w-5 h-5 stroke-[1.5]" />}
          onClick={() => {}}
          label="LOCATE"
        />
        <FloatingButton
          icon={<Camera className="w-6 h-6 stroke-[1.5]" />}
          onClick={() => setShowAddMemory(true)}
          variant="primary"
          label="CAPTURE"
        />
      </motion.div>

      {/* Bottom Controls */}
      <motion.div
        initial={{ y: 100, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ delay: 0.5, duration: 0.5 }}
        className="absolute bottom-8 left-6 right-6 z-10 flex gap-4"
      >
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98, filter: "brightness(1.05)" }}
          onClick={() => setIsPaused(!isPaused)}
          className="flex-1 bg-white/95 backdrop-blur-2xl rounded-[28px] shadow-[0_8px_40px_rgba(0,0,0,0.06)] px-6 py-4 flex items-center justify-center gap-3 active:shadow-[inset_0_2px_12px_rgba(0,0,0,0.08)] transition-all"
        >
          <Pause className="w-5 h-5 stroke-[1.5]" />
          <span className="font-black text-sm tracking-tight uppercase">Pause</span>
        </motion.button>

        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98, filter: "brightness(1.2)" }}
          onClick={() => setShowShareRoute(true)}
          className="flex-1 bg-black rounded-[28px] shadow-[0_8px_40px_rgba(0,0,0,0.15)] px-6 py-4 flex items-center justify-center gap-3 text-white active:shadow-[inset_0_2px_12px_rgba(255,255,255,0.2)] transition-all"
        >
          <Check className="w-5 h-5 stroke-[1.5]" />
          <span className="font-black text-sm tracking-tight uppercase">Finish</span>
        </motion.button>
      </motion.div>

      {/* Modals */}
      <AddMemoryModal isOpen={showAddMemory} onClose={() => setShowAddMemory(false)} />
      <ShareRouteModal isOpen={showShareRoute} onClose={() => setShowShareRoute(false)} />
    </div>
  );
}

function FloatingButton({
  icon,
  onClick,
  variant = "secondary",
  label,
}: {
  icon: React.ReactNode;
  onClick: () => void;
  variant?: "primary" | "secondary";
  label: string;
}) {
  return (
    <div className="flex flex-col items-center gap-2">
      <motion.button
        whileHover={{ scale: 1.08 }}
        whileTap={{ scale: 0.92, filter: variant === "primary" ? "brightness(1.2)" : "brightness(1.05)" }}
        onClick={onClick}
        className={`w-14 h-14 rounded-full shadow-[0_8px_32px_rgba(0,0,0,0.12)] flex items-center justify-center transition-all ${
          variant === "primary"
            ? "bg-black text-white active:shadow-[inset_0_2px_12px_rgba(255,255,255,0.2)]"
            : "bg-white/95 backdrop-blur-2xl text-black active:shadow-[inset_0_2px_12px_rgba(0,0,0,0.08)]"
        }`}
      >
        {icon}
      </motion.button>
      <span className="text-[9px] font-black tracking-wider uppercase text-[#6B6B6B]">{label}</span>
    </div>
  );
}