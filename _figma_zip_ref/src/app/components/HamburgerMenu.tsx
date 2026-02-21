import { motion, AnimatePresence } from "motion/react";
import { X, Home, Heart, MapPin, User, Settings } from "lucide-react";
import { useNavigate, useLocation } from "react-router";

interface HamburgerMenuProps {
  isOpen: boolean;
  onClose: () => void;
}

export function HamburgerMenu({ isOpen, onClose }: HamburgerMenuProps) {
  const navigate = useNavigate();
  const location = useLocation();

  const handleNavigate = (path: string) => {
    navigate(path);
    onClose();
  };

  const menuItems = [
    { path: "/", label: "HOME", icon: <Home className="w-5 h-5 stroke-[1.5]" /> },
    { path: "/memories", label: "MEMORIES", icon: <Heart className="w-5 h-5 stroke-[1.5]" /> },
    { path: "/cities", label: "CITIES", icon: <MapPin className="w-5 h-5 stroke-[1.5]" /> },
    { path: "/profile", label: "PROFILE", icon: <User className="w-5 h-5 stroke-[1.5]" /> },
    { path: "/settings", label: "SETTINGS", icon: <Settings className="w-5 h-5 stroke-[1.5]" /> },
  ];

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/30 backdrop-blur-sm z-40"
          />

          {/* Menu Panel */}
          <motion.div
            initial={{ x: "-100%" }}
            animate={{ x: 0 }}
            exit={{ x: "-100%" }}
            transition={{ type: "spring", damping: 30, stiffness: 300 }}
            className="fixed left-0 top-0 bottom-0 w-80 bg-white shadow-[8px_0_40px_rgba(0,0,0,0.08)] z-50 flex flex-col"
          >
            {/* Header */}
            <div className="p-6 border-b border-black/[0.06]">
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-2xl font-black tracking-tight">EXPLORE</h2>
                <motion.button
                  whileHover={{ scale: 1.1, rotate: 90 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={onClose}
                  className="p-2 hover:bg-black/5 rounded-full transition-all"
                >
                  <X className="w-6 h-6 stroke-[1.5]" />
                </motion.button>
              </div>

              {/* User Info */}
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-gradient-to-br from-[#52B788]/10 to-[#74C69D]/20 rounded-[20px] flex items-center justify-center text-2xl shadow-sm">
                  👧
                </div>
                <div>
                  <p className="font-black text-sm tracking-tight">CYBER KAKA</p>
                  <p className="text-xs text-[#6B6B6B] tracking-wide">EXPLORER</p>
                </div>
              </div>
            </div>

            {/* Navigation */}
            <div className="flex-1 p-4 overflow-y-auto">
              <div className="space-y-2">
                {menuItems.map((item, index) => (
                  <motion.button
                    key={item.path}
                    initial={{ x: -50, opacity: 0 }}
                    animate={{ x: 0, opacity: 1 }}
                    transition={{ delay: index * 0.05 }}
                    whileHover={{ scale: 1.02, x: 4 }}
                    whileTap={{ scale: 0.98 }}
                    onClick={() => handleNavigate(item.path)}
                    className={`w-full flex items-center gap-4 px-5 py-4 rounded-[24px] transition-all ${
                      location.pathname === item.path
                        ? "bg-[#52B788] text-white shadow-[0_4px_24px_rgba(82,183,136,0.2)]"
                        : "bg-[#FBFBF9] hover:bg-[#F5F5F3] text-black"
                    }`}
                  >
                    {item.icon}
                    <span className="font-black text-sm tracking-tight">{item.label}</span>
                  </motion.button>
                ))}
              </div>
            </div>

            {/* Footer */}
            <div className="p-4 border-t border-black/[0.06]">
              <p className="text-[10px] text-center text-[#6B6B6B] tracking-wider uppercase font-semibold">
                Journey Diary v1.0
              </p>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}