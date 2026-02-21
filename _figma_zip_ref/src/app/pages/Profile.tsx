import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { Menu, Shirt, MapPin, TrendingUp, Navigation, ChevronRight, Map } from "lucide-react";
import { useState } from "react";
import { HamburgerMenu } from "../components/HamburgerMenu";

export function Profile() {
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <div className="min-h-screen bg-[#FBFBF9] pb-20">
      {/* Header */}
      <motion.header
        initial={{ y: -50, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.5 }}
        className="sticky top-0 z-10 bg-white/90 backdrop-blur-2xl border-b border-black/[0.06]"
      >
        <div className="px-6 py-6 flex items-center justify-between">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95, filter: "brightness(1.1)" }}
            onClick={() => setMenuOpen(true)}
            className="p-2 rounded-full hover:bg-black/5 transition-all active:shadow-[inset_0_2px_8px_rgba(0,0,0,0.1)]"
          >
            <Menu className="w-6 h-6 stroke-[1.5]" />
          </motion.button>
          <h1 className="text-3xl font-black tracking-tight uppercase">Profile</h1>
          <div className="w-10" />
        </div>
      </motion.header>

      <div className="px-6 py-8 space-y-6">
        {/* Profile Card */}
        <motion.div
          initial={{ scale: 0.95, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.1, type: "spring", stiffness: 200 }}
          className="bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-8"
        >
          {/* Avatar - 8-bit Pixel Character */}
          <motion.div
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            transition={{
              delay: 0.3,
              type: "spring",
              stiffness: 200,
              damping: 15,
            }}
            className="flex justify-center mb-6"
          >
            <div className="relative">
              <div className="w-32 h-32 bg-gradient-to-br from-[#52B788]/10 to-[#74C69D]/20 rounded-[32px] shadow-[0_4px_24px_rgba(82,183,136,0.12)] flex items-center justify-center">
                {/* 8-bit Pixel Avatar */}
                <div className="text-6xl">👧</div>
              </div>
              {/* Subtle Glow */}
              <motion.div
                animate={{
                  scale: [1, 1.1, 1],
                  opacity: [0.2, 0, 0.2],
                }}
                transition={{
                  duration: 3,
                  repeat: Infinity,
                }}
                className="absolute inset-0 bg-[#52B788] rounded-[32px] blur-2xl -z-10"
              />
            </div>
          </motion.div>

          {/* Name & Bio */}
          <motion.div
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: 0.4 }}
            className="text-center"
          >
            <h2 className="text-2xl font-black mb-1 tracking-tight">CYBER KAKA</h2>
            <p className="text-[#6B6B6B] text-sm tracking-wide">EXPLORER</p>
          </motion.div>
        </motion.div>

        {/* Data Cards */}
        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.5 }}
          className="grid grid-cols-3 gap-3"
        >
          <DataCard
            icon={<MapPin className="w-5 h-5 stroke-[1.5]" />}
            label="TRIPS"
            value="200"
          />
          <DataCard
            icon={<TrendingUp className="w-5 h-5 stroke-[1.5]" />}
            label="DISTANCE"
            value="0km"
          />
          <DataCard
            icon={<Navigation className="w-5 h-5 stroke-[1.5]" />}
            label="CITIES"
            value="58"
          />
        </motion.div>

        {/* Action Sections */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.6 }}
          className="grid grid-cols-2 gap-4"
        >
          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98, filter: "brightness(1.1)" }}
            onClick={() => navigate("/equipment")}
            className="bg-white rounded-[32px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-6 flex flex-col items-center justify-center gap-3 active:shadow-[inset_0_2px_12px_rgba(144,169,160,0.12)] transition-all"
          >
            <div className="w-14 h-14 bg-[#52B788]/10 rounded-[20px] flex items-center justify-center">
              <Shirt className="w-7 h-7 stroke-[1.5] text-[#52B788]" />
            </div>
            <h3 className="text-sm font-black tracking-tight uppercase">Equipment</h3>
          </motion.button>

          <motion.button
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98, filter: "brightness(1.1)" }}
            onClick={() => navigate("/tracking")}
            className="bg-white rounded-[32px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-6 flex flex-col items-center justify-center gap-3 active:shadow-[inset_0_2px_12px_rgba(184,148,125,0.12)] transition-all"
          >
            <div className="w-14 h-14 bg-[#B8947D]/10 rounded-[20px] flex items-center justify-center">
              <Map className="w-7 h-7 stroke-[1.5] text-[#B8947D]" />
            </div>
            <h3 className="text-sm font-black tracking-tight uppercase">Journeys</h3>
          </motion.button>
        </motion.div>
      </div>

      {/* Hamburger Menu */}
      <HamburgerMenu isOpen={menuOpen} onClose={() => setMenuOpen(false)} />
    </div>
  );
}

function DataCard({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="bg-white rounded-[28px] shadow-[0_4px_32px_rgba(0,0,0,0.04)] p-4 flex flex-col items-center gap-2">
      <div className="text-[#6B6B6B]">{icon}</div>
      <p className="text-2xl font-black">{value}</p>
      <p className="text-[10px] text-[#6B6B6B] tracking-wider uppercase font-semibold">{label}</p>
    </div>
  );
}