import { motion } from "motion/react";
import { Bot, Footprints, Home, Users } from "lucide-react";
import type { ReactNode } from "react";
import { NavLink } from "react-router";

interface MainTabLayoutProps {
  title: string;
  children: ReactNode;
  contentClassName?: string;
  rightSlot?: ReactNode;
}

type TabItem = {
  to: string;
  label: string;
  Icon: React.ComponentType<{ className?: string }>;
  end?: boolean;
};

const tabItems: TabItem[] = [
  { to: "/", label: "Home", Icon: Home, end: true },
  { to: "/friends", label: "Friends", Icon: Users },
  { to: "/profile", label: "Profile", Icon: Bot },
  { to: "/lifelog", label: "Lifelog", Icon: Footprints },
];

export function MainTabLayout({ title, children, contentClassName, rightSlot }: MainTabLayoutProps) {
  return (
    <div className="min-h-screen bg-[#FBFBF9]">
      <motion.header
        initial={{ y: -40, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.45 }}
        className="sticky top-0 z-20 border-b border-black/[0.06] bg-white/90 backdrop-blur-2xl"
      >
        <div className="flex items-center justify-between px-6 py-6">
          <div className="h-10 w-10" />
          <h1 className="text-3xl font-black tracking-tight uppercase">{title}</h1>
          <div className="flex h-10 w-10 items-center justify-center">{rightSlot ?? null}</div>
        </div>
      </motion.header>

      <main className={`px-6 py-8 pb-24 ${contentClassName ?? ""}`}>{children}</main>
      <BottomTabNav />
    </div>
  );
}

function BottomTabNav() {
  return (
    <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-black/[0.06] bg-white/95 backdrop-blur-2xl">
      <div className="mx-auto grid max-w-xl grid-cols-4 gap-1 px-2 pb-[calc(env(safe-area-inset-bottom)+0.5rem)] pt-2">
        {tabItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              `flex flex-col items-center justify-center gap-1 rounded-2xl px-2 py-2 transition-all ${
                isActive ? "bg-[#52B788]/12 text-[#2D7A57]" : "text-[#6B6B6B] hover:bg-[#F5F5F3]"
              }`
            }
          >
            <item.Icon className="h-5 w-5 stroke-[1.8]" />
            <span className="text-[10px] font-black tracking-wide uppercase">{item.label}</span>
          </NavLink>
        ))}
      </div>
    </nav>
  );
}
