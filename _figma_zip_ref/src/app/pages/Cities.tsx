import { motion } from "motion/react";
import { useNavigate } from "react-router";
import { Menu, MapPin, Eye } from "lucide-react";
import { useState } from "react";
import { HamburgerMenu } from "../components/HamburgerMenu";

interface City {
  id: string;
  name: string;
  country: string;
  visits: number;
  memories: number;
  color: string;
}

const cities = [
  {
    name: "London",
    country: "United Kingdom",
    visits: 38,
    memories: 17,
    color: "#52B788",
  },
  {
    name: "Paris",
    country: "France",
    visits: 28,
    memories: 6,
    color: "#B8947D",
  },
  {
    name: "Tokyo",
    country: "Japan",
    visits: 7,
    memories: 14,
    color: "#74C69D",
  },
  {
    name: "New York",
    country: "United States",
    visits: 5,
    memories: 1,
    color: "#52B788",
  },
  {
    name: "Barcelona",
    country: "Spain",
    visits: 3,
    memories: 1,
    color: "#B8947D",
  },
];

export function Cities() {
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);

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
            onClick={() => setMenuOpen(true)}
            className="p-2 rounded-full hover:bg-black/5 transition-all"
          >
            <Menu className="w-6 h-6 stroke-[1.5]" />
          </motion.button>
          <h1 className="text-3xl font-black tracking-tight uppercase">Cities</h1>
          <div className="w-10" />
        </div>
      </motion.header>

      {/* Cities Grid */}
      <div className="px-6 py-8">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {cities.map((city, index) => (
            <CityCard key={city.name} city={city} index={index} />
          ))}
        </div>
      </div>

      {/* Hamburger Menu */}
      <HamburgerMenu isOpen={menuOpen} onClose={() => setMenuOpen(false)} />
    </div>
  );
}

function CityCard({ city, index }: { city: City; index: number }) {
  return (
    <motion.div
      initial={{ scale: 0.9, opacity: 0, y: 30 }}
      animate={{ scale: 1, opacity: 1, y: 0 }}
      transition={{
        delay: index * 0.08,
        type: "spring",
        stiffness: 200,
        damping: 20,
      }}
      whileHover={{ scale: 1.02, y: -4 }}
      whileTap={{ scale: 0.98 }}
      className="group cursor-pointer"
    >
      <div className="bg-white rounded-[36px] shadow-[0_8px_40px_rgba(0,0,0,0.04)] overflow-hidden">
        {/* Map Preview */}
        <div className="relative h-48 bg-[#F5F5F3] overflow-hidden">
          {/* Minimalist Grid Pattern */}
          <div className="absolute inset-0 opacity-10">
            <div
              className="w-full h-full"
              style={{
                backgroundImage: `repeating-linear-gradient(0deg, transparent, transparent 24px, rgba(0,0,0,0.5) 24px, rgba(0,0,0,0.5) 25px),
                                 repeating-linear-gradient(90deg, transparent, transparent 24px, rgba(0,0,0,0.5) 24px, rgba(0,0,0,0.5) 25px)`,
              }}
            />
          </div>

          {/* Location Pin - Subtle Animation */}
          <motion.div
            animate={{
              y: [0, -8, 0],
            }}
            transition={{
              duration: 2.5,
              repeat: Infinity,
              ease: "easeInOut",
            }}
            className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
          >
            <div 
              className="w-10 h-10 rounded-full shadow-[0_4px_16px_rgba(0,0,0,0.12)] flex items-center justify-center"
              style={{ backgroundColor: city.color }}
            >
              <MapPin className="w-5 h-5 stroke-[1.5] text-white fill-white" />
            </div>
          </motion.div>

          {/* Corner Label */}
          <div className="absolute bottom-3 left-3 text-[#6B6B6B]/50 text-[10px] font-black tracking-wider uppercase">
            Map View
          </div>
        </div>

        {/* City Info */}
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-2xl font-black tracking-tight">{city.name}</h3>
            <span className="px-3 py-1 bg-[#F5F5F3] rounded-full text-[10px] font-black tracking-wider uppercase">
              {city.country}
            </span>
          </div>

          <div className="flex items-center gap-6 text-sm">
            <div className="flex items-center gap-2">
              <Eye className="w-4 h-4 stroke-[1.5] text-[#6B6B6B]" />
              <span className="font-black text-black">{city.visits}</span>
              <span className="text-[#6B6B6B] text-xs tracking-wide uppercase font-semibold">Visits</span>
            </div>
            <div className="w-px h-4 bg-black/[0.1]" />
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-[#A8BDB5]" />
              <span className="font-black text-black">{city.memories}</span>
              <span className="text-[#6B6B6B] text-xs tracking-wide uppercase font-semibold">Memories</span>
            </div>
          </div>
        </div>

        {/* Hover Glow Effect */}
        <motion.div
          className="absolute inset-0 rounded-[36px] opacity-0 group-hover:opacity-100 pointer-events-none transition-opacity"
          style={{
            boxShadow: `inset 0 0 0 2px ${city.color}, 0 0 24px ${city.color}40`,
          }}
        />
      </div>
    </motion.div>
  );
}