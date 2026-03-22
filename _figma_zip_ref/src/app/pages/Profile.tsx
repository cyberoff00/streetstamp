import { motion } from "motion/react";
import { Bot, MapPin, Route, Settings, Shirt, StickyNote } from "lucide-react";
import { useNavigate } from "react-router";
import { MainTabLayout } from "../components/MainTabLayout";

type ProfileEntry = {
  title: string;
  subtitle: string;
  to: string;
  icon: React.ComponentType<{ className?: string }>;
  iconBg: string;
  iconColor: string;
};

const profileEntries: ProfileEntry[] = [
  {
    title: "Equipment",
    subtitle: "装备",
    to: "/equipment",
    icon: Shirt,
    iconBg: "bg-[#52B788]/12",
    iconColor: "text-[#3C9A71]",
  },
  {
    title: "My Cities",
    subtitle: "City Library",
    to: "/cities",
    icon: MapPin,
    iconBg: "bg-[#B8947D]/12",
    iconColor: "text-[#9B6B4A]",
  },
  {
    title: "My Journeys",
    subtitle: "我的旅程",
    to: "/tracking",
    icon: Route,
    iconBg: "bg-[#74C69D]/16",
    iconColor: "text-[#2F865B]",
  },
  {
    title: "My Memories",
    subtitle: "Journey Memory",
    to: "/memories",
    icon: StickyNote,
    iconBg: "bg-[#D9D2C3]/28",
    iconColor: "text-[#7F6952]",
  },
];

export function Profile() {
  const navigate = useNavigate();

  return (
    <MainTabLayout
      title="Profile"
      rightSlot={
        <button
          onClick={() => navigate("/settings")}
          className="flex h-10 w-10 items-center justify-center rounded-full transition-all hover:bg-black/5"
          aria-label="Open settings"
        >
          <Settings className="h-5 w-5 stroke-[1.8]" />
        </button>
      }
    >
      <div className="mx-auto w-full max-w-xl space-y-6">
        <motion.section
          initial={{ scale: 0.95, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.08, type: "spring", stiffness: 180 }}
          className="rounded-[36px] bg-white p-8 shadow-[0_8px_40px_rgba(0,0,0,0.04)]"
        >
          <div className="mb-6 flex justify-center">
            <div className="relative">
              <div className="flex h-32 w-32 items-center justify-center rounded-[32px] bg-gradient-to-br from-[#52B788]/12 to-[#74C69D]/22 shadow-[0_4px_24px_rgba(82,183,136,0.12)]">
                <Bot className="h-14 w-14 text-[#2E7C59]" strokeWidth={1.7} />
              </div>
              <motion.div
                animate={{ scale: [1, 1.1, 1], opacity: [0.2, 0, 0.2] }}
                transition={{ duration: 3, repeat: Infinity }}
                className="absolute inset-0 -z-10 rounded-[32px] bg-[#52B788] blur-2xl"
              />
            </div>
          </div>

          <div className="text-center">
            <h2 className="mb-1 text-2xl font-black tracking-tight">CYBER KAKA</h2>
            <p className="text-sm tracking-wide text-[#6B6B6B]">EXPLORER</p>
          </div>
        </motion.section>

        <motion.section
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.2 }}
          className="grid grid-cols-3 gap-3"
        >
          <DataCard label="Trips" value="200" />
          <DataCard label="Distance" value="0km" />
          <DataCard label="Cities" value="58" />
        </motion.section>

        <motion.section
          initial={{ y: 24, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.28 }}
          className="grid grid-cols-2 gap-4"
        >
          {profileEntries.map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.title}
                onClick={() => navigate(item.to)}
                className="rounded-[28px] bg-white p-5 text-left shadow-[0_8px_40px_rgba(0,0,0,0.04)] transition-all active:scale-[0.98] active:brightness-[1.02]"
              >
                <div className={`mb-4 flex h-12 w-12 items-center justify-center rounded-[16px] ${item.iconBg}`}>
                  <Icon className={`h-6 w-6 stroke-[1.7] ${item.iconColor}`} />
                </div>
                <h3 className="text-sm font-black tracking-tight">{item.title}</h3>
                <p className="mt-1 text-xs font-semibold uppercase tracking-wide text-[#6B6B6B]">{item.subtitle}</p>
              </button>
            );
          })}
        </motion.section>
      </div>
    </MainTabLayout>
  );
}

function DataCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-[24px] bg-white p-4 shadow-[0_4px_28px_rgba(0,0,0,0.04)]">
      <p className="text-2xl font-black">{value}</p>
      <p className="text-[10px] font-semibold uppercase tracking-wider text-[#6B6B6B]">{label}</p>
    </div>
  );
}
