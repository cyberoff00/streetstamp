import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { Play, Footprints } from "lucide-react";
import { MainTabLayout } from "../components/MainTabLayout";

export function Home() {
  const navigate = useNavigate();

  return (
    <MainTabLayout
      title="Home"
      contentClassName="flex min-h-[calc(100vh-12rem)] flex-col items-center justify-center overflow-hidden"
    >
      <div className="w-full max-w-xl text-center">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.2, duration: 0.8, ease: "easeOut" }}
        >
          <h1 className="text-7xl font-black mb-16 text-center tracking-tighter">
            JOURNEY
          </h1>
        </motion.div>

        {/* Start Button - Misty Green CTA */}
        <motion.button
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{
            delay: 0.5,
            type: "spring",
            stiffness: 200,
            damping: 15,
          }}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95, filter: "brightness(1.1)" }}
          onClick={() => navigate("/tracking")}
          className="relative w-64 h-64 rounded-full bg-[#52B788] shadow-[0_12px_48px_rgba(82,183,136,0.25)] flex items-center justify-center group active:shadow-[inset_0_4px_16px_rgba(0,0,0,0.08)]"
        >
          {/* Subtle Pulsing Glow */}
          <motion.div
            animate={{
              scale: [1, 1.2, 1],
              opacity: [0.3, 0, 0.3],
            }}
            transition={{
              duration: 2.5,
              repeat: Infinity,
              ease: "easeInOut",
            }}
            className="absolute inset-0 rounded-full bg-[#52B788] blur-3xl"
          />

          <div className="flex flex-col items-center gap-3 relative z-10">
            <Play className="w-10 h-10 text-white stroke-[1.5] fill-white" />
            <span className="text-white text-2xl font-black tracking-tight">START</span>
          </div>
        </motion.button>

        {/* Daily Mode Button */}
        <motion.button
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.8, duration: 0.6 }}
          whileHover={{ scale: 1.03 }}
          whileTap={{ scale: 0.97, filter: "brightness(0.98)" }}
          onClick={() => navigate("/tracking")}
          className="mt-12 px-8 py-4 border-[2px] border-[#B8947D] rounded-full flex items-center gap-3 bg-white shadow-[0_4px_24px_rgba(184,148,125,0.12)] hover:shadow-[0_8px_32px_rgba(184,148,125,0.2)] active:shadow-[inset_0_2px_12px_rgba(184,148,125,0.08)] transition-all"
        >
          <Footprints className="w-5 h-5 stroke-[1.5] text-[#B8947D]" />
          <span className="font-black text-sm tracking-tight uppercase text-[#B8947D]">Daily Mode</span>
        </motion.button>
      </div>
    </MainTabLayout>
  );
}
