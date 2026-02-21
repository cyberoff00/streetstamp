import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { Menu, Sparkles, Info, Shield, Palette, CreditCard, ChevronRight, Bell } from "lucide-react";
import { useState } from "react";
import { HamburgerMenu } from "../components/HamburgerMenu";

export function Settings() {
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
            whileTap={{ scale: 0.95 }}
            onClick={() => setMenuOpen(true)}
            className="p-2 rounded-full hover:bg-black/5 transition-all"
          >
            <Menu className="w-6 h-6 stroke-[1.5]" />
          </motion.button>
          <h1 className="text-3xl font-black tracking-tight uppercase">Settings</h1>
          <div className="w-10" />
        </div>
      </motion.header>

      <div className="px-6 py-8 space-y-8">
        {/* General Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="space-y-3"
        >
          <h2 className="text-xs font-black text-[#6B6B6B] uppercase tracking-wider px-2 mb-4">
            General
          </h2>
          <SettingItem
            icon={<Bell className="w-5 h-5 stroke-[1.5] text-[#B06D1D]" />}
            label="Notifications"
            onClick={() => {}}
          />
          <SettingItem
            icon={<Palette className="w-5 h-5 stroke-[1.5] text-[#B06D1D]" />}
            label="Theme"
            onClick={() => {}}
          />
        </motion.div>

        {/* Account Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="space-y-3"
        >
          <h2 className="text-xs font-black text-[#6B6B6B] uppercase tracking-wider px-2 mb-4">
            Account
          </h2>
          <SettingItem
            icon={<CreditCard className="w-5 h-5 stroke-[1.5] text-[#4CAF50]" />}
            label="Subscription"
            onClick={() => {}}
          />
        </motion.div>

        {/* App Info Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="space-y-3"
        >
          <h2 className="text-xs font-black text-[#6B6B6B] uppercase tracking-wider px-2 mb-4">
            Information
          </h2>
          <SettingItem
            icon={<Sparkles className="w-5 h-5 stroke-[1.5] text-[#B06D1D]" />}
            label="Check for Updates"
            badge="v1.0.0"
            onClick={() => {}}
          />
          <SettingItem
            icon={<Info className="w-5 h-5 stroke-[1.5]" />}
            label="About Us"
            onClick={() => navigate("/about")}
          />
          <SettingItem
            icon={<Shield className="w-5 h-5 stroke-[1.5]" />}
            label="Privacy Policy"
            onClick={() => navigate("/privacy")}
          />
        </motion.div>
      </div>

      {/* Hamburger Menu */}
      <HamburgerMenu isOpen={menuOpen} onClose={() => setMenuOpen(false)} />
    </div>
  );
}

function SettingItem({
  icon,
  label,
  badge,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  badge?: string;
  onClick: () => void;
}) {
  return (
    <motion.button
      whileHover={{ scale: 1.01, x: 4 }}
      whileTap={{ scale: 0.99, filter: "brightness(1.05)" }}
      onClick={onClick}
      className="w-full bg-white rounded-[32px] shadow-[0_4px_32px_rgba(0,0,0,0.04)] p-5 flex items-center gap-4 active:shadow-[inset_0_2px_12px_rgba(0,0,0,0.06)] transition-all"
    >
      <div className="w-12 h-12 bg-[#FBFBF9] rounded-[20px] flex items-center justify-center">
        {icon}
      </div>
      <span className="flex-1 text-left font-black text-sm tracking-tight uppercase">{label}</span>
      {badge && (
        <span className="px-3 py-1 bg-[#F5F5F3] rounded-full text-[10px] font-black tracking-wider uppercase">
          {badge}
        </span>
      )}
      <ChevronRight className="w-5 h-5 stroke-[1.5] text-[#6B6B6B]" />
    </motion.button>
  );
}
