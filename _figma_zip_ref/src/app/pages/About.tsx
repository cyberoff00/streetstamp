import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { ArrowLeft, Heart, Compass, Sparkles, Users, Mail, Globe } from "lucide-react";

export function About() {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-[#FBFBF9]">
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
            onClick={() => navigate("/settings")}
            className="flex items-center gap-2 p-2 rounded-full hover:bg-black/5 transition-all"
          >
            <ArrowLeft className="w-5 h-5 stroke-[1.5]" />
            <span className="font-black text-sm tracking-tight uppercase">Back</span>
          </motion.button>
          <h1 className="text-3xl font-black tracking-tight uppercase">About</h1>
          <div className="w-20" />
        </div>
      </motion.header>

      <div className="px-6 py-8 max-w-2xl mx-auto space-y-8">
        {/* Logo Section */}
        <motion.div
          initial={{ scale: 0.9, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.2, type: "spring", stiffness: 200 }}
          className="text-center"
        >
          <div className="inline-block p-10 bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] mb-6">
            <motion.div
              animate={{
                rotate: [0, 8, -8, 0],
              }}
              transition={{
                duration: 4,
                repeat: Infinity,
                ease: "easeInOut",
              }}
            >
              <Compass className="w-24 h-24 stroke-[1.5] text-[#52B788]" />
            </motion.div>
          </div>
          <h2 className="text-4xl font-black mb-3 tracking-tighter">JOURNEY DIARY</h2>
          <p className="text-[#6B6B6B] text-base tracking-wide">EXPLORE · RECORD · REMEMBER</p>
          <p className="text-[#6B6B6B]/50 text-xs mt-3 tracking-wider uppercase font-semibold">Version 1.0.0</p>
        </motion.div>

        {/* Mission Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.4 }}
          className="bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-8"
        >
          <div className="flex items-center gap-4 mb-5">
            <div className="w-14 h-14 bg-[#52B788]/10 rounded-[20px] flex items-center justify-center">
              <Heart className="w-7 h-7 stroke-[1.5] text-[#52B788]" />
            </div>
            <h3 className="text-2xl font-black tracking-tight">OUR MISSION</h3>
          </div>
          <p className="text-black leading-relaxed tracking-normal">
            Journey Diary is dedicated to helping every traveler record and cherish their adventures. We believe that every journey is a unique memory worth preserving and revisiting.
          </p>
        </motion.div>

        {/* Features Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.5 }}
          className="space-y-4"
        >
          <FeatureCard
            icon={<Compass className="w-6 h-6 stroke-[1.5] text-[#52B788]" />}
            title="PRECISE TRACKING"
            description="Advanced GPS technology records every step of your journey"
          />
          <FeatureCard
            icon={<Sparkles className="w-6 h-6 stroke-[1.5] text-[#B8947D]" />}
            title="BEAUTIFUL MEMORIES"
            description="Capture and preserve the precious moments of your travels"
          />
          <FeatureCard
            icon={<Users className="w-6 h-6 stroke-[1.5] text-[#A8BDB5]" />}
            title="SHARE ADVENTURES"
            description="Share your routes and stories with friends and fellow explorers"
          />
        </motion.div>

        {/* Contact Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.6 }}
          className="bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-8 text-center"
        >
          <h3 className="text-xl font-black mb-5 tracking-tight uppercase">Contact Us</h3>
          <div className="space-y-3">
            <div className="flex items-center justify-center gap-3 text-[#6B6B6B]">
              <Mail className="w-5 h-5 stroke-[1.5]" />
              <span className="text-sm tracking-wide">support@journeydiary.com</span>
            </div>
            <div className="flex items-center justify-center gap-3 text-[#6B6B6B]">
              <Globe className="w-5 h-5 stroke-[1.5]" />
              <span className="text-sm tracking-wide">www.journeydiary.com</span>
            </div>
          </div>
        </motion.div>

        {/* Footer */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.8 }}
          className="text-center text-xs text-[#6B6B6B] pt-8 space-y-2"
        >
          <p className="tracking-wider uppercase font-semibold">© 2026 Journey Diary. All rights reserved.</p>
          <p className="text-[#6B6B6B]/50 tracking-wide">Crafted with precision for explorers</p>
        </motion.div>
      </div>
    </div>
  );
}

function FeatureCard({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  return (
    <motion.div
      whileHover={{ scale: 1.01, x: 4 }}
      className="bg-white rounded-[32px] shadow-[0_4px_24px_rgba(0,0,0,0.04)] p-6"
    >
      <div className="flex items-start gap-4">
        <div className="w-12 h-12 bg-[#FBFBF9] rounded-[20px] flex items-center justify-center flex-shrink-0">
          {icon}
        </div>
        <div>
          <h4 className="font-black text-sm mb-2 tracking-tight uppercase">{title}</h4>
          <p className="text-[#6B6B6B] text-sm leading-relaxed">{description}</p>
        </div>
      </div>
    </motion.div>
  );
}