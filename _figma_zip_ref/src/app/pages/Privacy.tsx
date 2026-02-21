import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { ArrowLeft, Shield, Lock, Eye, Database, UserCheck, Mail, Phone } from "lucide-react";

export function Privacy() {
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
          <h1 className="text-3xl font-black tracking-tight uppercase">Privacy</h1>
          <div className="w-20" />
        </div>
      </motion.header>

      <div className="px-6 py-8 max-w-2xl mx-auto space-y-6">
        {/* Intro */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-8"
        >
          <div className="flex items-center gap-4 mb-5">
            <div className="w-14 h-14 bg-[#5B9BD5]/10 rounded-[20px] flex items-center justify-center">
              <Shield className="w-7 h-7 stroke-[1.5] text-[#5B9BD5]" />
            </div>
            <h2 className="text-2xl font-black tracking-tight">YOUR PRIVACY MATTERS</h2>
          </div>
          <p className="text-black leading-relaxed mb-4">
            Journey Diary is committed to protecting your privacy and data security. This policy explains how we collect, use, and safeguard your personal information.
          </p>
          <p className="text-xs text-[#6B6B6B] tracking-wide uppercase font-semibold">
            Last Updated: February 13, 2026
          </p>
        </motion.div>

        {/* Privacy Sections */}
        <PrivacySection
          icon={<Database className="w-6 h-6 stroke-[1.5] text-[#FF6B35]" />}
          title="DATA COLLECTION"
          content="We collect location data, travel records, and personal memories you provide while using the app. This information is used solely to enhance your experience."
          delay={0.3}
        />

        <PrivacySection
          icon={<Lock className="w-6 h-6 stroke-[1.5] text-[#5B9BD5]" />}
          title="DATA SECURITY"
          content="We use industry-standard encryption to protect your data. All sensitive information is encrypted and stored with strict access controls."
          delay={0.4}
        />

        <PrivacySection
          icon={<Eye className="w-6 h-6 stroke-[1.5] text-[#FF8A65]" />}
          title="DATA USAGE"
          content="Your location and travel data is used for route tracking, statistics, and personalized recommendations. We never sell or share your personal information with third parties."
          delay={0.5}
        />

        <PrivacySection
          icon={<UserCheck className="w-6 h-6 stroke-[1.5] text-[#5B9BD5]" />}
          title="YOUR RIGHTS"
          content="You have the right to access, modify, or delete your personal data at any time. Manage your privacy preferences in settings or contact our support team."
          delay={0.6}
        />

        {/* Contact Section */}
        <motion.div
          initial={{ y: 50, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.7 }}
          className="bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] p-8"
        >
          <h3 className="text-xl font-black mb-4 tracking-tight uppercase">Questions?</h3>
          <p className="text-black mb-5 leading-relaxed">
            If you have any questions or concerns about our privacy policy, please don't hesitate to contact us:
          </p>
          <div className="space-y-3">
            <div className="flex items-center gap-3 text-[#6B6B6B]">
              <Mail className="w-5 h-5 stroke-[1.5]" />
              <span className="text-sm tracking-wide">privacy@journeydiary.com</span>
            </div>
            <div className="flex items-center gap-3 text-[#6B6B6B]">
              <Phone className="w-5 h-5 stroke-[1.5]" />
              <span className="text-sm tracking-wide">+1 (800) 123-4567</span>
            </div>
          </div>
        </motion.div>

        {/* Footer */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.8 }}
          className="text-center text-xs text-[#6B6B6B] pt-4"
        >
          <p className="tracking-wider uppercase font-semibold">© 2026 Journey Diary. All rights reserved.</p>
        </motion.div>
      </div>
    </div>
  );
}

function PrivacySection({
  icon,
  title,
  content,
  delay,
}: {
  icon: React.ReactNode;
  title: string;
  content: string;
  delay: number;
}) {
  return (
    <motion.div
      initial={{ y: 50, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ delay }}
      whileHover={{ scale: 1.01 }}
      className="bg-white rounded-[32px] shadow-[0_4px_24px_rgba(0,0,0,0.04)] p-6"
    >
      <div className="flex items-start gap-4">
        <div className="w-12 h-12 bg-[#FBFBF9] rounded-[20px] flex items-center justify-center flex-shrink-0">
          {icon}
        </div>
        <div>
          <h3 className="font-black text-sm mb-2 tracking-tight uppercase">{title}</h3>
          <p className="text-[#6B6B6B] text-sm leading-relaxed">{content}</p>
        </div>
      </div>
    </motion.div>
  );
}